#!/bin/bash

# 日志文件路径
LOG_FILE="/var/log/disk_mount.log"

# 颜色定义，提高可读性
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
    echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

# 错误日志函数
error_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 错误: $1" | tee -a $LOG_FILE
    echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S') - 错误: $1${NC}"
}

# 成功日志函数
success_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 成功: $1" | tee -a $LOG_FILE
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') - 成功: $1${NC}"
}

# 检查命令执行结果
check_result() {
    if [ $? -ne 0 ]; then
        error_log "$1 失败"
        exit 1
    fi
}

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    error_log "此脚本必须以root权限运行"
    exit 1
fi

# 显示磁盘信息
log "列出磁盘信息..."
lsblk
check_result "lsblk"

# 提示用户选择新磁盘
while true; do
    echo -e "${YELLOW}请输入要挂载到/data目录的新磁盘设备 (例如: /dev/sdb):${NC}"
    read DISK_ADD
    
    # 检查设备是否存在
    if [ -b "$DISK_ADD" ]; then
        # 检查磁盘是否已挂载
        if mount | grep -q "$DISK_ADD"; then
            error_log "磁盘 $DISK_ADD 已经被挂载。请选择其他磁盘。"
        else
            # 检查磁盘是否已有分区
            if lsblk "$DISK_ADD" | grep -q "${DISK_ADD:5}[0-9]"; then
                error_log "磁盘 $DISK_ADD 已有分区。请选择一个干净的磁盘或使用其他工具管理已分区的磁盘。"
                echo -e "${YELLOW}可用磁盘:${NC}"
                lsblk | grep disk
                continue
            fi
            break
        fi
    else
        error_log "设备 $DISK_ADD 不存在"
        echo -e "${YELLOW}可用磁盘:${NC}"
        lsblk | grep disk
    fi
done

# 确认磁盘选择
echo -e "${RED}警告: $DISK_ADD 上的所有数据将会丢失!${NC}"
echo -e "${YELLOW}您确定要使用 $DISK_ADD 吗? (y/n)${NC}"
read CONFIRM
if [ "$CONFIRM" != "y" ]; then
    log "操作已被用户取消"
    exit 0
fi

# 询问挂载点
echo -e "${YELLOW}请输入挂载点 (默认: /data):${NC}"
read MOUNT_POINT
if [ -z "$MOUNT_POINT" ]; then
    MOUNT_POINT="/data"
fi

# 询问文件系统类型
echo -e "${YELLOW}请选择文件系统类型:${NC}"
echo "1) xfs (推荐)"
echo "2) ext4"
read FS_CHOICE
if [ "$FS_CHOICE" == "2" ]; then
    FS_TYPE="ext4"
    FS_OPTS="defaults"
else
    FS_TYPE="xfs"
    FS_OPTS="defaults"
fi

# 创建分区
log "正在创建 $DISK_ADD 的新分区..."
echo -e "n\np\n1\n\n\nw" | fdisk "$DISK_ADD"
check_result "在 $DISK_ADD 上创建分区"

# 等待内核更新分区表
log "等待分区表更新..."
sleep 2
partprobe "$DISK_ADD"
check_result "更新分区表"

# 获取新分区名称
PART_NAME="${DISK_ADD}1"
if [[ "$DISK_ADD" == *"nvme"* ]]; then
    PART_NAME="${DISK_ADD}p1"
fi

# 等待分区可用
log "等待新分区可用..."
sleep 2

# 格式化分区
log "正在使用 $FS_TYPE 格式化分区 $PART_NAME..."
if [ "$FS_TYPE" == "xfs" ]; then
    mkfs.xfs "$PART_NAME"
    check_result "使用 xfs 格式化 $PART_NAME"
else
    mkfs.ext4 "$PART_NAME"
    check_result "使用 ext4 格式化 $PART_NAME"
fi

# 如果挂载点不存在则创建
if [ ! -d "$MOUNT_POINT" ]; then
    log "正在创建挂载点 $MOUNT_POINT..."
    mkdir -p "$MOUNT_POINT"
    check_result "创建挂载点 $MOUNT_POINT"
else
    log "挂载点 $MOUNT_POINT 已存在"
    
    # 检查挂载点是否已被使用
    if mount | grep -q " on $MOUNT_POINT "; then
        error_log "挂载点 $MOUNT_POINT 已被使用"
        exit 1
    fi
fi

# 挂载分区
log "正在将 $PART_NAME 挂载到 $MOUNT_POINT..."
mount "$PART_NAME" "$MOUNT_POINT"
check_result "将 $PART_NAME 挂载到 $MOUNT_POINT"

# 添加到 fstab 以实现持久挂载
log "正在添加条目到 /etc/fstab 以实现持久挂载..."
if grep -q "$PART_NAME" /etc/fstab; then
    log "$PART_NAME 的条目已存在于 /etc/fstab 中"
else
    echo "$PART_NAME $MOUNT_POINT $FS_TYPE $FS_OPTS 0 0" >> /etc/fstab
    check_result "添加条目到 /etc/fstab"
fi

# 设置适当的权限
log "正在设置 $MOUNT_POINT 的权限..."
chmod 755 "$MOUNT_POINT"
check_result "设置权限"

# 显示结果
success_log "磁盘 $DISK_ADD 已成功分区，使用 $FS_TYPE 格式化，并挂载到 $MOUNT_POINT"
echo -e "${GREEN}当前磁盘使用情况:${NC}"
df -h | grep "$PART_NAME"

log "磁盘挂载操作已成功完成"