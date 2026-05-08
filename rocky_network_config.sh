#!/bin/bash
#
# Rocky Linux 9.6 网络配置脚本
# 使用 nmcli 修改 IP 地址、子网掩码、网关和 DNS 地址
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
    exit 1
fi

# 显示当前网络连接
show_connections() {
    echo -e "${YELLOW}当前网络连接:${NC}"
    nmcli connection show | grep -v "loopback"
    echo ""
}

# 获取用户输入
get_connection_name() {
    show_connections
    read -p "请输入要修改的网络连接名称: " CONNECTION_NAME
    
    # 检查连接是否存在
    if ! nmcli connection show | grep -q "$CONNECTION_NAME"; then
        echo -e "${RED}错误: 连接 '$CONNECTION_NAME' 不存在${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}已选择连接: $CONNECTION_NAME${NC}"
    echo ""
}

# 配置 IP 地址、子网掩码和网关
configure_ip() {
    echo -e "${YELLOW}配置 IP 地址、子网掩码和网关${NC}"
    
    # 获取当前配置
    CURRENT_IP=$(nmcli -g ipv4.addresses connection show "$CONNECTION_NAME" 2>/dev/null)
    CURRENT_GATEWAY=$(nmcli -g ipv4.gateway connection show "$CONNECTION_NAME" 2>/dev/null)
    
    echo -e "当前 IP 配置: ${GREEN}$CURRENT_IP${NC}"
    echo -e "当前网关: ${GREEN}$CURRENT_GATEWAY${NC}"
    echo ""
    
    # 获取新的 IP 配置
    read -p "请输入新的 IP 地址 (例如, 192.168.1.100): " IP_ADDRESS
    read -p "请输入子网掩码前缀 (例如, 24 表示 255.255.255.0): " NETMASK
    read -p "请输入新的网关地址 (例如, 192.168.1.1): " GATEWAY
    
    # 应用 IP 配置
    echo -e "${YELLOW}正在应用 IP 配置...${NC}"
    nmcli connection modify "$CONNECTION_NAME" ipv4.addresses "$IP_ADDRESS/$NETMASK"
    nmcli connection modify "$CONNECTION_NAME" ipv4.gateway "$GATEWAY"
    nmcli connection modify "$CONNECTION_NAME" ipv4.method manual
    
    echo -e "${GREEN}IP 配置已更新${NC}"
    echo ""
}

# 配置 DNS 服务器
configure_dns() {
    echo -e "${YELLOW}配置 DNS 服务器${NC}"
    
    # 获取当前 DNS 配置
    CURRENT_DNS=$(nmcli -g ipv4.dns connection show "$CONNECTION_NAME" 2>/dev/null)
    
    echo -e "当前 DNS 服务器: ${GREEN}$CURRENT_DNS${NC}"
    echo ""
    
    # 获取新的 DNS 配置
    read -p "请输入主要 DNS 服务器 (例如, 8.8.8.8): " PRIMARY_DNS
    read -p "请输入次要 DNS 服务器 (可选, 按回车跳过): " SECONDARY_DNS
    
    # 应用 DNS 配置
    echo -e "${YELLOW}正在应用 DNS 配置...${NC}"
    if [ -z "$SECONDARY_DNS" ]; then
        nmcli connection modify "$CONNECTION_NAME" ipv4.dns "$PRIMARY_DNS"
    else
        nmcli connection modify "$CONNECTION_NAME" ipv4.dns "$PRIMARY_DNS,$SECONDARY_DNS"
    fi
    
    echo -e "${GREEN}DNS 配置已更新${NC}"
    echo ""
}

# 应用配置并重启网络连接
apply_changes() {
    echo -e "${YELLOW}正在应用所有更改并重启网络连接...${NC}"
    nmcli connection down "$CONNECTION_NAME" && nmcli connection up "$CONNECTION_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}网络配置已成功应用${NC}"
        
        # 显示新的网络配置
        echo -e "\n${YELLOW}新的网络配置:${NC}"
        echo -e "${GREEN}连接名称:${NC} $CONNECTION_NAME"
        echo -e "${GREEN}IP 地址/掩码:${NC} $(nmcli -g ipv4.addresses connection show "$CONNECTION_NAME")"
        echo -e "${GREEN}网关:${NC} $(nmcli -g ipv4.gateway connection show "$CONNECTION_NAME")"
        echo -e "${GREEN}DNS 服务器:${NC} $(nmcli -g ipv4.dns connection show "$CONNECTION_NAME")"
    else
        echo -e "${RED}应用网络配置时出错${NC}"
        exit 1
    fi
}

# 主函数
main() {
    echo -e "${GREEN}===== Rocky Linux 9.6 网络配置工具 =====${NC}"
    echo -e "${YELLOW}此脚本将帮助您配置 IP 地址、子网掩码、网关和 DNS 服务器${NC}"
    echo ""
    
    get_connection_name
    configure_ip
    configure_dns
    
    # 确认更改
    echo -e "${YELLOW}即将应用以下更改:${NC}"
    echo -e "连接名称: ${GREEN}$CONNECTION_NAME${NC}"
    echo -e "IP 地址/掩码: ${GREEN}$IP_ADDRESS/$NETMASK${NC}"
    echo -e "网关: ${GREEN}$GATEWAY${NC}"
    if [ -z "$SECONDARY_DNS" ]; then
        echo -e "DNS 服务器: ${GREEN}$PRIMARY_DNS${NC}"
    else
        echo -e "DNS 服务器: ${GREEN}$PRIMARY_DNS, $SECONDARY_DNS${NC}"
    fi
    echo ""
    
    read -p "应用这些更改? (y/n): " CONFIRM
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        apply_changes
    else
        echo -e "${YELLOW}操作已取消${NC}"
        exit 0
    fi
}

# 执行主函数
main