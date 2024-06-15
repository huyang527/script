#!/bin/bash
echo "修改root密码为Kmsoft@km123456"
echo "Kmsoft@km123456" | passwd --stdin root

echo "请输入要设置的 IP 地址："
read IP_ADDR

echo "请输入子网掩码："
read SUBNET_MASK

echo "请输入网关地址："
read GATEWAY

cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-ens192
DEVICE=ens192
BOOTPROTO=static
IPADDR=$IP_ADDR
NETMASK=$SUBNET_MASK
GATEWAY=$GATEWAY
ONBOOT=yes
EOF

systemctl restart network
systemctl restart sshd