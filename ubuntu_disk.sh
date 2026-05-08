#!/bin/bash

# 检查是否为root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本"
  exit 1
fi

# 列出所有磁盘信息
echo "当前磁盘信息如下："
sudo fdisk -l | grep "Disk /dev"

# 提示用户输入新磁盘设备名称
echo "请输入要添加的磁盘设备名称（例如 /dev/sdb）："
read DISK_ADD

# 确认磁盘是否存在
if ! [ -b "$DISK_ADD" ]; then
  echo "错误：磁盘 $DISK_ADD 不存在或不是一个有效的块设备！"
  exit 1
fi

# 显示现有物理卷
echo "正在创建物理卷..."
pvcreate $DISK_ADD

# 显示现有卷组信息
echo "当前系统中的卷组如下："
vgdisplay -s

# 提示用户输入卷组名称
echo "请输入目标卷组名称（如 ubuntu-vg）："
read VG_NAME

# 判断卷组是否存在
if ! vgdisplay $VG_NAME > /dev/null; then
  echo "错误：卷组 $VG_NAME 不存在！"
  exit 1
fi

# 扩展卷组
echo "正在扩展卷组 $VG_NAME ..."
vgextend $VG_NAME $DISK_ADD

# 创建逻辑卷并使用全部可用空间
echo "正在创建逻辑卷 data ..."
lvcreate -l 100%FREE -n data $VG_NAME

# 格式化逻辑卷为 xfs 文件系统
echo "正在格式化逻辑卷为 xfs 文件系统 ..."
mkfs.xfs /dev/$VG_NAME/data

# 创建挂载目录
mkdir -p /data

# 挂载逻辑卷到/data目录
mount /dev/$VG_NAME/data /data

# 将挂载信息写入 fstab 实现开机自动挂载
echo "/dev/$VG_NAME/data /data xfs defaults 0 0" >> /etc/fstab

# 显示最终结果
echo ""
echo "✅ 完成！逻辑卷已成功挂载到 /data 目录"
df -Th | grep "/data"
