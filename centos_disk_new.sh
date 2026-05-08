#!/bin/bash

# 日志文件路径
LOG_FILE="/var/log/disk_mount.log"

# 记录日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# 检查命令执行结果
check_result() {
    if [ $? -ne 0 ]; then
        log "错误: $1 失败"
        exit 1
    fi
}

# 列出所有磁盘信息
log "列出磁盘信息..."
fdisk -l
check_result "fdisk -l"

# 提示用户输入新磁盘设备名称
while true; do
    echo "开始挂载新磁盘到/data目录,请输入新磁盘名称:(如/dev/sdb):"
    read DISK_ADD
    
    # 检查设备是否存在
    if [ -b $DISK_ADD ]; then
        break
    else
        log "错误: 设备 $DISK_ADD 不存在"
        echo "设备不存在，请重新输入"
    fi
done

# 创建物理卷
log "创建物理卷 $DISK_ADD..."
pvcreate $DISK_ADD
check_result "pvcreate $DISK_ADD"

# 显示卷组信息
log "显示卷组信息..."
vgdisplay -s
check_result "vgdisplay -s"

# 提示用户输入卷组名称
while true; do
    echo "请输入卷组名称:"
    read VG_NAME
    
    # 检查卷组是否存在
    if vgdisplay $VG_NAME >/dev/null 2>&1; then
        break
    else
        log "错误: 卷组 $VG_NAME 不存在"
        echo "卷组不存在，请重新输入"
    fi
done

# 扩展卷组
log "扩展卷组 $VG_NAME..."
vgextend $VG_NAME $DISK_ADD
check_result "vgextend $VG_NAME $DISK_ADD"

# 创建逻辑卷并使用全部可用空间
log "创建逻辑卷 data..."
lvcreate -l 100%FREE -n data $VG_NAME
check_result "lvcreate -l 100%FREE -n data $VG_NAME"

# 格式化逻辑卷为xfs文件系统
log "格式化逻辑卷为xfs文件系统..."
mkfs.xfs /dev/$VG_NAME/data
check_result "mkfs.xfs /dev/$VG_NAME/data"

# 检查挂载点是否存在
if [ -d /data ]; then
    log "警告: /data 目录已存在"
    echo "/data 目录已存在，是否继续？(y/n)"
    read CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        log "用户取消操作"
        exit 0
    fi
else
    # 创建挂载目录
    log "创建挂载目录 /data..."
    mkdir -p /data
    check_result "mkdir -p /data"
fi

# 挂载逻辑卷到/data目录
log "挂载逻辑卷到 /data..."
mount /dev/$VG_NAME/data /data
check_result "mount /dev/$VG_NAME/data /data"

# 检查fstab条目是否已存在
if grep -q "/dev/$VG_NAME/data" /etc/fstab; then
    log "警告: fstab中已存在该设备的挂载信息"
else
    # 将挂载信息写入fstab实现开机自动挂载
    log "将挂载信息写入fstab..."
    echo "/dev/$VG_NAME/data /data xfs defaults 0 0" >> /etc/fstab
    check_result "写入fstab"
fi

log "磁盘挂载完成"
