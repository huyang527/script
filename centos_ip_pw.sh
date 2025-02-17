#!/bin/bash

# 配置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 重置颜色

# 自动检测主网卡
NIC=$(nmcli -t -f DEVICE,TYPE device | grep ethernet | cut -d: -f1 | head -1)
CONFIG_FILE="/etc/sysconfig/network-scripts/ifcfg-${NIC}"

# 帮助信息
show_help() {
    echo -e "${YELLOW}使用说明:"
    echo "  -h           显示帮助信息"
    echo "  -a <IP>      指定IP地址"
    echo "  -g <网关>    指定网关地址"
    echo "  -s           静默模式（使用默认配置）"
    echo -e "示例: $0 -a 192.168.1.100 -g 192.168.1.1${NC}"
    exit 0
}

# 输入验证函数
validate_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && 
           ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# 处理参数
while getopts ":ha:g:s" opt; do
    case $opt in
        h) show_help ;;
        a) IP_ADDR=$OPTARG ;;
        g) GATEWAY=$OPTARG ;;
        s) SILENT=1 ;;
        \?) echo -e "${RED}无效参数: -$OPTARG${NC}" >&2; exit 1 ;;
    esac
done

# 交互式修改root密码
echo -e "${YELLOW}=== 正在修改root密码 ===${NC}"
if ! passwd root; then
    echo -e "${RED}密码修改失败，请检查日志${NC}"
    exit 1
fi

# 获取网络配置信息
if [ -z "$SILENT" ]; then
    while true; do
        read -p "请输入IP地址: " IP_ADDR
        validate_ip $IP_ADDR && break
        echo -e "${RED}无效的IP地址格式，请重新输入${NC}"
    done

    while true; do
        read -p "请输入网关地址: " GATEWAY
        validate_ip $GATEWAY && break
        echo -e "${RED}无效的网关地址格式，请重新输入${NC}"
    done
fi

# 备份原有配置
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
echo -e "${YELLOW}备份网络配置到 ${BACKUP_FILE}${NC}"
cp $CONFIG_FILE $BACKUP_FILE || {
    echo -e "${RED}配置文件备份失败${NC}"
    exit 1
}

# 生成新配置
cat <<EOF > $CONFIG_FILE
DEVICE=$NIC
BOOTPROTO=static
IPADDR=$IP_ADDR
NETMASK=255.255.255.0
GATEWAY=$GATEWAY
DNS1=8.8.8.8
DNS2=114.114.114.114
ONBOOT=yes
EOF

# 检查配置语法
if ! ifdown $NIC && ifup $NIC; then
    echo -e "${RED}网络配置错误，正在恢复备份...${NC}"
    cp $BACKUP_FILE $CONFIG_FILE
    ifup $NIC
    exit 1
fi

# 重启服务
echo -e "${YELLOW}应用网络配置...${NC}"
systemctl restart NetworkManager >/dev/null 2>&1 || {
    echo -e "${RED}网络服务重启失败${NC}"
    exit 1
}

echo -e "${GREEN}=== 配置完成 ==="
echo -e "IP地址: \t$IP_ADDR"
echo -e "网关地址: \t$GATEWAY"
echo -e "网卡名称: \t$NIC${NC}"
