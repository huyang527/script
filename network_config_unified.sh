#!/usr/bin/env bash

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

die() {
    echo -e "${RED}错误: $*${NC}" >&2
    exit 1
}

info() {
    echo -e "${YELLOW}$*${NC}"
}

success() {
    echo -e "${GREEN}$*${NC}"
}

run() {
    "$@"
    local status=$?
    if [ "$status" -ne 0 ]; then
        die "命令执行失败: $*"
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "请使用 root 权限运行，例如: sudo bash $0"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

trim_value() {
    printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

interface_exists() {
    local interface="$1"

    [ -n "$interface" ] || return 1
    ip -br addr 2>/dev/null | awk '{print $1}' | awk -F'@' '{print $1}' | grep -Fxq "$interface" && return 0
    ip -br link 2>/dev/null | awk '{print $1}' | awk -F'@' '{print $1}' | grep -Fxq "$interface" && return 0
    ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | awk -F'@' '{print $1}' | grep -Fxq "$interface" && return 0
    ip addr show dev "$interface" >/dev/null 2>&1 && return 0
    ip link show dev "$interface" >/dev/null 2>&1 && return 0

    return 1
}

list_interface_names() {
    ip -br addr 2>/dev/null | awk '{print $1}' | awk -F'@' '{print $1}'
}

valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    local IFS=.
    local -a octets
    read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        [ "$octet" -ge 0 ] 2>/dev/null && [ "$octet" -le 255 ] || return 1
    done
}

cidr_to_netmask() {
    local cidr="$1"
    local mask=""
    local full=$((cidr / 8))
    local partial=$((cidr % 8))

    for i in 0 1 2 3; do
        if [ "$i" -lt "$full" ]; then
            mask+="255"
        elif [ "$i" -eq "$full" ]; then
            mask+="$((256 - 2 ** (8 - partial)))"
        else
            mask+="0"
        fi
        [ "$i" -lt 3 ] && mask+="."
    done

    echo "$mask"
}

detect_os() {
    OS_ID="unknown"
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
    fi
}

service_is_active() {
    local service="$1"

    command_exists systemctl || return 1
    systemctl is-active --quiet "$service" 2>/dev/null
}

nmcli_has_connection() {
    local interface="$1"

    command_exists nmcli || return 1
    [ -n "$interface" ] || return 1
    nmcli -t -f DEVICE connection show --active 2>/dev/null | grep -Fxq "$interface" && return 0
    nmcli -t -f DEVICE connection show 2>/dev/null | grep -Fxq "$interface"
}

netplan_has_config() {
    local interface="$1"

    command_exists netplan || return 1
    [ -d /etc/netplan ] || return 1
    find /etc/netplan -maxdepth 1 -name "*.yaml" -type f | grep -q . || return 1

    if [ -n "$interface" ]; then
        grep -R "^[[:space:]]*$interface:" /etc/netplan/*.yaml >/dev/null 2>&1
        return $?
    fi

    return 0
}

ifcfg_has_config() {
    local interface="$1"

    [ -d /etc/sysconfig/network-scripts ] || return 1
    [ -n "$interface" ] || return 0
    [ -f "/etc/sysconfig/network-scripts/ifcfg-$interface" ]
}

detect_backend_for_interface() {
    local interface="$1"

    if netplan_has_config "$interface"; then
        echo "netplan"
    elif service_is_active NetworkManager && nmcli_has_connection "$interface"; then
        echo "nmcli"
    elif ifcfg_has_config "$interface"; then
        echo "ifcfg"
    elif command_exists nmcli && nmcli_has_connection "$interface"; then
        echo "nmcli"
    elif command_exists netplan && [ -d /etc/netplan ]; then
        echo "netplan"
    elif [ -d /etc/sysconfig/network-scripts ]; then
        echo "ifcfg"
    else
        echo "unknown"
    fi
}

choose_backend() {
    local detected
    detected="$(detect_backend_for_interface "$INTERFACE")"

    echo ""
    info "检测到系统: $OS_ID"
    if [ "$detected" != "unknown" ]; then
        info "自动检测到网卡 $INTERFACE 当前适合使用: $detected"
        read -r -p "直接使用自动检测结果请回车；如需手动选择输入 1) netplan 2) nmcli 3) ifcfg: " choice
    else
        info "未能自动识别网卡 $INTERFACE 的网络配置方式，请手动选择。"
        echo "1) netplan（Ubuntu 常用）"
        echo "2) nmcli / NetworkManager（Rocky、RHEL 8/9、部分 Kylin 常用）"
        echo "3) ifcfg 文件（CentOS 7、部分 Kylin 常用）"
        read -r -p "请输入选项: " choice
    fi

    case "$choice" in
        "")
            [ "$detected" != "unknown" ] || die "无法自动识别网络配置方式，请手动选择。"
            BACKEND="$detected"
            ;;
        1)
            BACKEND="netplan"
            ;;
        2)
            BACKEND="nmcli"
            ;;
        3)
            BACKEND="ifcfg"
            ;;
        *)
            die "无效选项: $choice"
            ;;
    esac
}

show_interfaces() {
    info "当前网络接口:"
    ip -br addr
}

ask_common_config() {
    show_interfaces
    read -r -p "请输入网卡名称，例如 ens192、ens33、eth0: " INTERFACE
    INTERFACE="$(trim_value "$INTERFACE")"
    [ -n "$INTERFACE" ] || die "网卡名称不能为空"
    if ! interface_exists "$INTERFACE"; then
        info "脚本识别到的网卡名称:"
        list_interface_names
        die "网卡 '$INTERFACE' 不存在"
    fi

    while true; do
        read -r -p "请输入静态 IP 地址: " IP_ADDR
        valid_ipv4 "$IP_ADDR" && break
        echo "IP 地址格式不正确。"
    done

    while true; do
        read -r -p "请输入子网前缀 [默认: 24]: " CIDR
        CIDR="${CIDR:-24}"
        [[ "$CIDR" =~ ^[0-9]+$ ]] && [ "$CIDR" -ge 1 ] && [ "$CIDR" -le 32 ] && break
        echo "子网前缀必须是 1-32。"
    done

    while true; do
        read -r -p "请输入网关地址: " GATEWAY
        valid_ipv4 "$GATEWAY" && break
        echo "网关地址格式不正确。"
    done

    read -r -p "请输入 DNS 服务器，多个用空格分隔 [默认: 223.5.5.5 114.114.114.114]: " DNS_INPUT
    DNS_SERVERS="${DNS_INPUT:-223.5.5.5 114.114.114.114}"
}

confirm_config() {
    echo ""
    info "即将应用以下配置:"
    echo "配置方式: $BACKEND"
    echo "网卡: $INTERFACE"
    echo "IP/前缀: $IP_ADDR/$CIDR"
    echo "网关: $GATEWAY"
    echo "DNS: $DNS_SERVERS"
    echo ""
    read -r -p "确认应用? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || die "用户取消操作"
}

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
        info "已备份: $file"
    fi
}

apply_netplan() {
    command_exists netplan || die "未找到 netplan 命令"
    [ -d /etc/netplan ] || die "/etc/netplan 不存在"

    local backup_dir="/etc/netplan/backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"
    find /etc/netplan -maxdepth 1 -name "*.yaml" -exec cp {} "$backup_dir"/ \;

    local dns_yaml=""
    for dns in $DNS_SERVERS; do
        valid_ipv4 "$dns" || die "DNS 地址格式不正确: $dns"
        dns_yaml="${dns_yaml}          - $dns
"
    done

    cat > /etc/netplan/01-static-ip.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      addresses:
        - "$IP_ADDR/$CIDR"
      routes:
        - to: default
          via: "$GATEWAY"
      nameservers:
        addresses:
$dns_yaml        search: []
EOF

    info "正在验证 netplan 配置..."
    if ! netplan try --timeout 30; then
        info "验证失败，正在恢复备份。"
        rm -f /etc/netplan/*.yaml
        cp "$backup_dir"/*.yaml /etc/netplan/ 2>/dev/null || true
        die "netplan 配置验证失败"
    fi

    run netplan apply
}

apply_nmcli() {
    command_exists nmcli || die "未找到 nmcli 命令"

    local connection
    connection="$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$INTERFACE" '$2==dev{print $1; exit}')"
    if [ -z "$connection" ]; then
        connection="$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v dev="$INTERFACE" '$2==dev{print $1; exit}')"
    fi
    if [ -z "$connection" ]; then
        read -r -p "未自动找到连接名，请输入 NetworkManager 连接名: " connection
        [ -n "$connection" ] || die "连接名不能为空"
        nmcli connection show "$connection" >/dev/null 2>&1 || die "连接 $connection 不存在"
    fi

    local dns_csv
    dns_csv="$(echo "$DNS_SERVERS" | tr ' ' ',')"

    run nmcli connection modify "$connection" ipv4.addresses "$IP_ADDR/$CIDR"
    run nmcli connection modify "$connection" ipv4.gateway "$GATEWAY"
    run nmcli connection modify "$connection" ipv4.dns "$dns_csv"
    run nmcli connection modify "$connection" ipv4.method manual

    info "正在重启连接: $connection"
    nmcli connection down "$connection" || true
    run nmcli connection up "$connection"
}

apply_ifcfg() {
    [ -d /etc/sysconfig/network-scripts ] || die "/etc/sysconfig/network-scripts 不存在"

    local config_file="/etc/sysconfig/network-scripts/ifcfg-$INTERFACE"
    local netmask
    local dns_lines=""
    local index=1

    netmask="$(cidr_to_netmask "$CIDR")"
    backup_file "$config_file"

    for dns in $DNS_SERVERS; do
        valid_ipv4 "$dns" || die "DNS 地址格式不正确: $dns"
        dns_lines="${dns_lines}DNS${index}=${dns}
"
        index=$((index + 1))
    done

    cat > "$config_file" <<EOF
DEVICE=$INTERFACE
NAME=$INTERFACE
BOOTPROTO=static
IPADDR=$IP_ADDR
PREFIX=$CIDR
NETMASK=$netmask
GATEWAY=$GATEWAY
ONBOOT=yes
$dns_lines
EOF

    if command_exists nmcli; then
        nmcli connection reload || true
        nmcli connection down "$INTERFACE" || true
        nmcli connection up "$INTERFACE" || systemctl restart NetworkManager
    elif command_exists ifdown && command_exists ifup; then
        ifdown "$INTERFACE" || true
        run ifup "$INTERFACE"
    elif systemctl list-unit-files network.service >/dev/null 2>&1; then
        run systemctl restart network
    else
        info "配置文件已写入，但未找到可用的网络重启命令，请手动重启网络。"
    fi
}

main() {
    require_root
    detect_os
    ask_common_config
    choose_backend
    confirm_config

    case "$BACKEND" in
        netplan)
            apply_netplan
            ;;
        nmcli)
            apply_nmcli
            ;;
        ifcfg)
            apply_ifcfg
            ;;
        *)
            die "未知配置方式: $BACKEND"
            ;;
    esac

    success "网络配置已更新。当前网卡信息:"
    ip addr show "$INTERFACE"
}

main "$@"
