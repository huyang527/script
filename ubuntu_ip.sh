#!/bin/bash

# 查看网口名称
sudo ip addr

# 定义网络接口名称
echo "输入网口名称："
read INTERFACE

# 定义静态 IP 地址
echo "请输入要设置的 IP 地址："
read IP_ADDR

# 定义子网掩码（CIDR格式）
echo "请输入子网掩码（默认为24，对应255.255.255.0）："
read NETMASK_CIDR
NETMASK_CIDR=${NETMASK_CIDR:-24}

# 定义网关
echo "请输入网关地址："
read GATEWAY

# 定义 DNS 服务器
echo "请输入DNS服务器（默认为223.5.5.5 114.114.114.114）："
read DNS_INPUT
DNS_SERVERS=${DNS_INPUT:-"223.5.5.5 114.114.114.114"}

# 备份现有配置
echo "备份现有网络配置..."
BACKUP_DIR="/etc/netplan/backup"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
sudo mkdir -p $BACKUP_DIR
sudo find /etc/netplan -name "*.yaml" -exec cp {} $BACKUP_DIR/{}.$TIMESTAMP \;

# 清理现有配置文件
echo "清理现有网络配置文件..."
sudo rm -f /etc/netplan/*.yaml

# 生成 netplan 配置文件内容（使用现代语法）
NETPLAN_CONFIG=$(cat <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      addresses:
        - "$IP_ADDR/$NETMASK_CIDR"
      routes:
        - to: default
          via: "$GATEWAY"
      nameservers:
        addresses:
          - $(echo $DNS_SERVERS | sed 's/ /\n          - /g')
        search: []
EOF
)

# 写入配置文件
echo "创建新的网络配置文件..."
echo "$NETPLAN_CONFIG" | sudo tee /etc/netplan/01-netcfg.yaml > /dev/null

# 验证配置
echo "验证网络配置..."
sudo netplan try --timeout 30 || { 
  echo "配置验证失败，恢复备份..."
  sudo find $BACKUP_DIR -name "*.yaml.$TIMESTAMP" -exec bash -c 'sudo cp "$1" "${1%.*.*}"' _ {} \;
  exit 1
}

# 应用配置
echo "应用网络配置..."
sudo netplan apply

echo "网络配置已更新，请检查网络连接状态"
ip addr show $INTERFACE