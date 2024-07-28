#!/bin/bash

# 启用 root 用户并设置密码
echo "正在启用 root 用户并设置密码..."
sudo passwd root

# 编辑 SSH 配置文件以允许 root 登录
echo "正在修改 SSH 配置文件..."
sudo sed -i '/PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config

# 重启 SSH 服务
echo "正在重启 SSH 服务..."
sudo service ssh restart

echo "完成！现在可以使用 root 用户通过 SSH 登录。"