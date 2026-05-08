#!/bin/bash

# 脚本名称: kylin_disk_new.sh
# 功能描述: 在Kylin系统中添加并挂载新硬盘到/data目录
# 使用方法: sudo bash kylin_disk_new.sh

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请使用root权限运行此脚本"
    exit 1
fi

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

# 检查必要工具是否安装
check_tools() {
    local tools=("fdisk" "lvm2" "xfsprogs")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null && ! rpm -q $tool &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "警告: 以下工具未安装: ${missing_tools[*]}"
        log "尝试安装缺失的工具..."
        
        # 检测包管理器类型
        if command -v apt &> /dev/null; then
            apt update
            apt install -y ${missing_tools[*]}
        elif command -v yum &> /dev/null; then
            yum install -y ${missing_tools[*]}
        else
            log "错误: 无法确定包管理器类型，请手动安装缺失的工具"
            exit 1
        fi
        
        check_result "安装必要工具"
    fi
}

# 检查必要工具
log "检查必要工具..."
check_tools

# 列出所有磁盘信息
log "列出磁盘信息..."
fdisk -l
check_result "fdisk -l"

# 提示用户输入新磁盘设备名称
while true; do
    echo "开始挂载新磁盘到/data目录,请输入新磁盘名称:(如/dev/sdb):"
    read DISK_ADD
    
    # 检查设备是否存在
    if [ -b "$DISK_ADD" ]; then
        # 检查设备是否已被挂载或使用
        if mount | grep -q "$DISK_ADD" || pvdisplay | grep -q "$DISK_ADD"; then
            log "警告: 设备 $DISK_ADD 已被挂载或已被LVM使用"
            echo "设备已被挂载或已被LVM使用，是否继续？(y/n)"
            read CONTINUE
            if [ "$CONTINUE" != "y" ]; then
                continue
            fi
        fi
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
    echo "请输入卷组名称(如果不存在将创建新卷组):"
    read VG_NAME
    
    # 检查卷组是否存在
    if ! vgdisplay $VG_NAME &>/dev/null; then
        log "卷组 $VG_NAME 不存在，将创建新卷组"
        vgcreate $VG_NAME $DISK_ADD
        check_result "vgcreate $VG_NAME $DISK_ADD"
        break
    else
        log "扩展卷组 $VG_NAME..."
        vgextend $VG_NAME $DISK_ADD
        check_result "vgextend $VG_NAME $DISK_ADD"
        break
    fi
done

# 提示用户输入逻辑卷名称
echo "请输入逻辑卷名称(默认为data):"
read LV_NAME
LV_NAME=${LV_NAME:-data}

# 检查逻辑卷是否已存在
if lvdisplay /dev/$VG_NAME/$LV_NAME &>/dev/null; then
    log "警告: 逻辑卷 $LV_NAME 已存在"
    echo "逻辑卷 $LV_NAME 已存在，是否扩展？(y/n)"
    read EXTEND_LV
    if [ "$EXTEND_LV" = "y" ]; then
        log "扩展逻辑卷 $LV_NAME..."
        lvextend -l +100%FREE /dev/$VG_NAME/$LV_NAME
        check_result "lvextend -l +100%FREE /dev/$VG_NAME/$LV_NAME"
        
        # 检查文件系统类型并扩展
        FS_TYPE=$(blkid -o value -s TYPE /dev/$VG_NAME/$LV_NAME)
        if [ "$FS_TYPE" = "xfs" ]; then
            log "扩展XFS文件系统..."
            xfs_growfs /dev/$VG_NAME/$LV_NAME
            check_result "xfs_growfs /dev/$VG_NAME/$LV_NAME"
        elif [ "$FS_TYPE" = "ext4" ]; then
            log "扩展EXT4文件系统..."
            resize2fs /dev/$VG_NAME/$LV_NAME
            check_result "resize2fs /dev/$VG_NAME/$LV_NAME"
        else
            log "警告: 未知的文件系统类型 $FS_TYPE，无法自动扩展"
        fi
    else
        log "用户取消扩展逻辑卷"
    fi
else
    # 创建逻辑卷并使用全部可用空间
    log "创建逻辑卷 $LV_NAME..."
    lvcreate -l 100%FREE -n $LV_NAME $VG_NAME
    check_result "lvcreate -l 100%FREE -n $LV_NAME $VG_NAME"

    # 提示用户选择文件系统类型
    echo "请选择文件系统类型(1:xfs, 2:ext4)，默认为xfs:"
    read FS_CHOICE
    FS_CHOICE=${FS_CHOICE:-1}

    if [ "$FS_CHOICE" = "2" ]; then
        # 格式化逻辑卷为ext4文件系统
        log "格式化逻辑卷为ext4文件系统..."
        mkfs.ext4 /dev/$VG_NAME/$LV_NAME
        check_result "mkfs.ext4 /dev/$VG_NAME/$LV_NAME"
        FS_TYPE="ext4"
    else
        # 格式化逻辑卷为xfs文件系统
        log "格式化逻辑卷为xfs文件系统..."
        mkfs.xfs /dev/$VG_NAME/$LV_NAME
        check_result "mkfs.xfs /dev/$VG_NAME/$LV_NAME"
        FS_TYPE="xfs"
    fi
fi

# 提示用户输入挂载点
echo "请输入挂载点(默认为/data):"
read MOUNT_POINT
MOUNT_POINT=${MOUNT_POINT:-/data}

# 检查挂载点是否存在
if [ -d "$MOUNT_POINT" ]; then
    log "警告: $MOUNT_POINT 目录已存在"
    echo "$MOUNT_POINT 目录已存在，是否继续？(y/n)"
    read CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        log "用户取消操作"
        exit 0
    fi
else
    # 创建挂载目录
    log "创建挂载目录 $MOUNT_POINT..."
    mkdir -p $MOUNT_POINT
    check_result "mkdir -p $MOUNT_POINT"
fi

# 检查是否已挂载
if mount | grep -q "$MOUNT_POINT"; then
    log "警告: $MOUNT_POINT 已被挂载"
    echo "$MOUNT_POINT 已被挂载，是否卸载并重新挂载？(y/n)"
    read REMOUNT
    if [ "$REMOUNT" = "y" ]; then
        log "卸载 $MOUNT_POINT..."
        umount $MOUNT_POINT
        check_result "umount $MOUNT_POINT"
    else
        log "用户取消重新挂载"
        exit 0
    fi
fi

# 挂载逻辑卷到指定目录
log "挂载逻辑卷到 $MOUNT_POINT..."
mount /dev/$VG_NAME/$LV_NAME $MOUNT_POINT
check_result "mount /dev/$VG_NAME/$LV_NAME $MOUNT_POINT"

# 检查fstab条目是否已存在
if grep -q "/dev/$VG_NAME/$LV_NAME" /etc/fstab; then
    log "警告: fstab中已存在该设备的挂载信息"
else
    # 将挂载信息写入fstab实现开机自动挂载
    log "将挂载信息写入fstab..."
    echo "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT $FS_TYPE defaults 0 0" >> /etc/fstab
    check_result "写入fstab"
fi

# 设置目录权限
log "设置 $MOUNT_POINT 目录权限..."
chmod 755 $MOUNT_POINT
check_result "chmod 755 $MOUNT_POINT"

log "磁盘挂载完成"
echo "磁盘挂载完成，挂载点: $MOUNT_POINT"
echo "文件系统类型: $FS_TYPE"
echo "磁盘使用情况:"
df -h $MOUNT_POINT