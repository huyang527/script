#!/bin/bash

# 查看网口名称
sudo ip addr

# 定义网络接口名称
echo "输入网口名称："
read INTERFACE

# 定义静态 IP 地址
echo "请输入要设置的 IP 地址："
read IP_ADDR

# 定义子网掩码
NETMASK="255.255.255.0"

# 定义网关
echo "请输入网关地址："
read GATEWAY

# 定义 DNS 服务器
DNS_SERVERS="223.5.5.5 114.114.114.114"

# 生成 netplan 配置文件内容
NETPLAN_CONFIG=$(cat <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      addresses: [$IP_ADDR/$NETMASK]
      gateway4: $GATEWAY
      nameservers:
        addresses: [$DNS_SERVERS]
EOF
)

# 写入配置文件
echo "$NETPLAN_CONFIG" | sudo tee /etc/netplan/01-network-manager-all.yaml > /dev/null

# 应用配置
sudo netplan apply