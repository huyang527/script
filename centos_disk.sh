#!/bin/bash

echo "开始挂载新磁盘到/data目录,请输入新磁盘名称:(如/dev/sdb)"
fdisk -l
read DISK_ADD
pvcreate $DISK_ADD

echo "请输入卷组名称"
vgdisplay -s
read VG_NAME
vgextend $VG_NAME /dev/$DISK_ADD
lvcreate -l 100%FREE -n data $VG_NAME
mkfs.xfs /dev/$VG_NAME/data
mkdir /data
mount /dev/$VG_NAME/data /data
echo "/dev/$VG_NAME/data /data xfs defaults 0 2" >> /etc/fstab
