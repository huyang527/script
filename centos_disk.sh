#!/bin/bash
# 列出所有磁盘信息
fdisk -l

# 提示用户输入新磁盘设备名称
echo "开始挂载新磁盘到/data目录,请输入新磁盘名称:(如/dev/sdb):"
read DISK_ADD

# 创建物理卷
pvcreate $DISK_ADD

# 显示卷组信息
vgdisplay -s
# 提示用户输入卷组名称
echo "请输入卷组名称"
read VG_NAME

# 扩展卷组
vgextend $VG_NAME $DISK_ADD
# 创建逻辑卷并使用全部可用空间
lvcreate -l 100%FREE -n data $VG_NAME
# 格式化逻辑卷为xfs文件系统
mkfs.xfs /dev/$VG_NAME/data
# 创建挂载目录
mkdir -p /data
# 挂载逻辑卷到/data目录
mount /dev/$VG_NAME/data /data
# 将挂载信息写入fstab实现开机自动挂载
echo "/dev/$VG_NAME/data /data xfs defaults 0 0" >> /etc/fstab