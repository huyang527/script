#!/bin/bash

# Kylin系统网络配置脚本
# 用于修改IP地址、网关和DNS

# 显示当前网络接口信息
echo "当前网络接口信息："
ip addr

# 获取网络接口名称
echo "请输入网络接口名称（例如：ens33, eth0）："
read INTERFACE

# 检查接口是否存在
if ! ip link show "$INTERFACE" &>/dev/null; then
    echo "错误：网络接口 '$INTERFACE' 不存在！"
    exit 1
fi

# 获取IP地址
echo "请输入要设置的 IP 地址："
read IP_ADDR

# 验证IP地址格式
if ! [[ $IP_ADDR =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "错误：IP地址格式不正确！"
    exit 1
fi

# 获取网关地址
echo "请输入网关地址："
read GATEWAY

# 验证网关地址格式
if ! [[ $GATEWAY =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "错误：网关地址格式不正确！"
    exit 1
fi

# 获取DNS地址
echo "请输入DNS服务器地址（多个地址用空格分隔，如不输入则使用默认值）："
read DNS_INPUT

# 如果用户未输入DNS，则使用默认值
if [ -z "$DNS_INPUT" ]; then
    DNS_SERVERS="223.5.5.5 114.114.114.114"
else
    DNS_SERVERS="$DNS_INPUT"
fi

# 子网掩码（默认为24位，即255.255.255.0）
NETMASK="255.255.255.0"

# 检查网络配置目录是否存在
if [ ! -d "/etc/sysconfig/network-scripts" ]; then
    echo "错误：/etc/sysconfig/network-scripts 目录不存在！"
    echo "此脚本仅适用于基于 CentOS/RHEL 的 Kylin 系统。"
    exit 1
fi

# 备份原配置文件
CONFIG_FILE="/etc/sysconfig/network-scripts/ifcfg-$INTERFACE"
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    echo "已备份原网络配置到 ${CONFIG_FILE}.bak"
fi

# 格式化DNS服务器为配置文件格式
DNS_FORMATTED=""
DNS_COUNT=1
for DNS in $DNS_SERVERS; do
    DNS_FORMATTED="${DNS_FORMATTED}DNS${DNS_COUNT}=${DNS}\n"
    DNS_COUNT=$((DNS_COUNT+1))
done

# 生成网络配置文件
cat <<EOF > "$CONFIG_FILE"
DEVICE=$INTERFACE
BOOTPROTO=static
IPADDR=$IP_ADDR
NETMASK=$NETMASK
GATEWAY=$GATEWAY
ONBOOT=yes
$(echo -e "$DNS_FORMATTED")
EOF

# 应用配置
echo "应用网络配置..."

# 尝试使用不同的网络重启命令
if command -v nmcli &>/dev/null; then
    echo "使用 NetworkManager 重启网络..."
    nmcli connection down "$INTERFACE" || true
    nmcli connection up "$INTERFACE"
    RESTART_STATUS=$?
else
    echo "使用传统方式重启网络..."
    if command -v ifdown &>/dev/null && command -v ifup &>/dev/null; then
        ifdown "$INTERFACE" || true
        ifup "$INTERFACE"
        RESTART_STATUS=$?
    else
        echo "警告：无法找到网络重启命令，请手动重启网络。"
        RESTART_STATUS=0
    fi
fi

# 检查网络重启状态
if [ $RESTART_STATUS -ne 0 ]; then
    echo "网络配置应用失败，正在恢复备份..."
    if [ -f "${CONFIG_FILE}.bak" ]; then
        cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
        if command -v nmcli &>/dev/null; then
            nmcli connection down "$INTERFACE" || true
            nmcli connection up "$INTERFACE"
        elif command -v ifdown &>/dev/null && command -v ifup &>/dev/null; then
            ifdown "$INTERFACE" || true
            ifup "$INTERFACE"
        fi
    fi
    exit 1
fi

# 验证网络连接
echo "验证网络连接..."
sleep 2

# 测试网关连通性
ping -c 3 $GATEWAY > /dev/null
if [ $? -eq 0 ]; then
    echo "网关连接正常！"
else
    echo "警告：无法连接到网关，请检查网络配置！"
fi

# 显示新的网络配置
echo -e "\n当前网络配置："
ip addr show $INTERFACE

echo -e "\n完成！网络配置已更新。"