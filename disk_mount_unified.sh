#!/usr/bin/env bash

set -o pipefail

LOG_FILE="/var/log/disk_mount.log"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${YELLOW}$*${NC}"
    log "$*"
}

success() {
    echo -e "${GREEN}$*${NC}"
    log "$*"
}

die() {
    echo -e "${RED}错误: $*${NC}" >&2
    log "错误: $*"
    exit 1
}

run() {
    "$@"
    local status=$?
    if [ "$status" -ne 0 ]; then
        die "命令执行失败: $*"
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "请使用 root 权限运行，例如: sudo bash $0"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_packages() {
    local packages=("$@")

    if [ "${#packages[@]}" -eq 0 ]; then
        return
    fi

    info "尝试安装缺少的软件包: ${packages[*]}"
    if command_exists apt; then
        run apt update
        run apt install -y "${packages[@]}"
    elif command_exists dnf; then
        run dnf install -y "${packages[@]}"
    elif command_exists yum; then
        run yum install -y "${packages[@]}"
    else
        die "无法识别包管理器，请手动安装: ${packages[*]}"
    fi
}

ensure_tools() {
    local missing=()

    command_exists lsblk || missing+=("util-linux")
    command_exists fdisk || missing+=("util-linux")
    command_exists partprobe || missing+=("parted")

    if [ "$MODE" = "lvm" ]; then
        command_exists pvcreate || missing+=("lvm2")
        command_exists vgdisplay || missing+=("lvm2")
        command_exists lvcreate || missing+=("lvm2")
    fi

    if [ "$FS_TYPE" = "xfs" ]; then
        command_exists mkfs.xfs || missing+=("xfsprogs")
    elif [ "$FS_TYPE" = "ext4" ]; then
        command_exists mkfs.ext4 || missing+=("e2fsprogs")
    fi

    install_packages "${missing[@]}"
}

detect_os() {
    OS_ID="unknown"
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
    fi
}

root_mount_source() {
    if command_exists findmnt; then
        findmnt -n -o SOURCE / 2>/dev/null
    else
        awk '$2=="/"{print $1; exit}' /proc/mounts
    fi
}

source_disk_type() {
    local source="$1"

    [ -n "$source" ] || return 1
    lsblk -nr -o TYPE "$source" 2>/dev/null | head -n 1
}

detect_current_disk_mode() {
    local source
    local type

    source="$(root_mount_source)"
    type="$(source_disk_type "$source")"

    if [ "$type" = "lvm" ] || [[ "$source" == /dev/mapper/* ]]; then
        echo "lvm"
    elif [ "$type" = "part" ] || [ "$type" = "disk" ]; then
        echo "partition"
    else
        echo "unknown"
    fi
}

fallback_mode_by_os() {
    case "$OS_ID" in
        rocky)
            echo "partition"
            ;;
        *)
            echo "lvm"
            ;;
    esac
}

ask_mode() {
    local detected
    local recommended

    detected="$(detect_current_disk_mode)"
    if [ "$detected" = "unknown" ]; then
        recommended="$(fallback_mode_by_os)"
    else
        recommended="$detected"
    fi

    echo ""
    info "检测到系统: $OS_ID"
    if [ "$detected" != "unknown" ]; then
        info "检测到当前根分区使用方式: $detected"
    else
        info "未能识别当前根分区使用方式，按系统类型推荐: $recommended"
    fi
    echo "请选择添加硬盘方式:"
    echo "1) LVM 扩容/创建逻辑卷"
    echo "2) 直接分区、格式化并挂载"
    read -r -p "直接使用自动检测/推荐结果请回车；如需手动选择输入 1) lvm 2) partition [默认: $recommended]: " choice

    case "$choice" in
        "")
            MODE="$recommended"
            ;;
        1)
            MODE="lvm"
            ;;
        2)
            MODE="partition"
            ;;
        *)
            die "无效选项: $choice"
            ;;
    esac
}

ask_fs_type() {
    read -r -p "请选择文件系统类型 1) xfs 2) ext4 [默认: xfs]: " choice
    case "${choice:-1}" in
        1)
            FS_TYPE="xfs"
            ;;
        2)
            FS_TYPE="ext4"
            ;;
        *)
            die "无效文件系统选项: $choice"
            ;;
    esac
}

list_disks() {
    info "当前磁盘信息:"
    lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS 2>/dev/null || lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT
}

ask_disk() {
    while true; do
        read -r -p "请输入要添加的磁盘设备，例如 sdb、/dev/sdb 或 /dev/nvme1n1: " DISK_ADD
        [ -n "$DISK_ADD" ] || continue
        if [[ "$DISK_ADD" != /dev/* ]]; then
            DISK_ADD="/dev/$DISK_ADD"
        fi

        if [ ! -b "$DISK_ADD" ]; then
            echo "设备不存在或不是块设备。"
            list_disks
            continue
        fi

        if mount | grep -q "^$DISK_ADD"; then
            echo "该设备已经挂载，请选择其他磁盘。"
            continue
        fi

        if [ "$MODE" = "partition" ] && lsblk -nr -o TYPE "$DISK_ADD" | grep -qx "part"; then
            echo "该磁盘已有分区。直接分区模式会重写分区表，请选择空盘或改用 LVM 模式。"
            continue
        fi

        echo -e "${RED}警告: 继续操作可能清除或覆盖 $DISK_ADD 上的数据。${NC}"
        read -r -p "确认使用该磁盘? (y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && break
    done
}

ask_mount_point() {
    read -r -p "请输入挂载点 [默认: /data]: " MOUNT_POINT
    MOUNT_POINT="${MOUNT_POINT:-/data}"
}

prepare_mount_point() {
    if [ -d "$MOUNT_POINT" ]; then
        if mountpoint -q "$MOUNT_POINT"; then
            die "挂载点 $MOUNT_POINT 已经被使用"
        fi
        read -r -p "$MOUNT_POINT 已存在，是否继续使用? (y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || die "用户取消操作"
    else
        run mkdir -p "$MOUNT_POINT"
    fi
}

fstab_add_once() {
    local source="$1"
    local target="$2"
    local fs="$3"

    if grep -Eq "^[^#[:space:]]+[[:space:]]+$target[[:space:]]+" /etc/fstab || grep -qF "$source" /etc/fstab; then
        info "/etc/fstab 已存在相关挂载记录，跳过写入。"
    else
        echo "$source $target $fs defaults 0 0" >> /etc/fstab
    fi
}

partition_name() {
    if [[ "$DISK_ADD" =~ (nvme|mmcblk) ]]; then
        echo "${DISK_ADD}p1"
    else
        echo "${DISK_ADD}1"
    fi
}

mount_partition_mode() {
    local part

    info "正在创建新分区..."
    printf 'n\np\n1\n\n\nw\n' | fdisk "$DISK_ADD" >/tmp/disk_mount_fdisk.log 2>&1
    if [ "$?" -ne 0 ]; then
        cat /tmp/disk_mount_fdisk.log >&2
        die "在 $DISK_ADD 上创建分区失败"
    fi

    sleep 2
    run partprobe "$DISK_ADD"
    part="$(partition_name)"
    sleep 2

    info "正在格式化 $part 为 $FS_TYPE..."
    if [ "$FS_TYPE" = "xfs" ]; then
        run mkfs.xfs -f "$part"
    else
        run mkfs.ext4 -F "$part"
    fi

    prepare_mount_point
    run mount "$part" "$MOUNT_POINT"
    fstab_add_once "$part" "$MOUNT_POINT" "$FS_TYPE"
}

extend_existing_lv() {
    local lv_path="$1"
    local fs_type

    run lvextend -l +100%FREE "$lv_path"
    fs_type="$(blkid -o value -s TYPE "$lv_path" 2>/dev/null || true)"

    if [ "$fs_type" = "xfs" ]; then
        run xfs_growfs "$lv_path"
    elif [ "$fs_type" = "ext4" ]; then
        run resize2fs "$lv_path"
    else
        info "逻辑卷已扩容，但文件系统类型为 ${fs_type:-未知}，请手动扩展文件系统。"
    fi
}

pv_vg_name() {
    pvs --noheadings -o vg_name "$1" 2>/dev/null | awk '{$1=$1; print; exit}'
}

ensure_pv_in_vg() {
    local disk="$1"
    local vg_name="$2"
    local current_vg

    current_vg="$(pv_vg_name "$disk")"

    if pvs "$disk" >/dev/null 2>&1; then
        if [ -n "$current_vg" ]; then
            if [ "$current_vg" = "$vg_name" ]; then
                info "$disk 已经属于卷组 $vg_name，跳过 pvcreate/vgextend。"
                return
            fi
            die "$disk 已经属于卷组 $current_vg，不能加入 $vg_name"
        fi

        info "$disk 已经是物理卷，跳过 pvcreate。"
    else
        info "正在创建物理卷 $disk..."
        run pvcreate "$disk"
    fi

    if vgdisplay "$vg_name" >/dev/null 2>&1; then
        info "正在扩展卷组 $vg_name..."
        run vgextend "$vg_name" "$disk"
    else
        info "卷组 $vg_name 不存在，正在创建..."
        run vgcreate "$vg_name" "$disk"
    fi
}

mount_lvm_mode() {
    local lv_path

    info "当前卷组:"
    vgdisplay -s || true

    read -r -p "请输入卷组名称；不存在则创建新卷组: " VG_NAME
    [ -n "$VG_NAME" ] || die "卷组名称不能为空"

    ensure_pv_in_vg "$DISK_ADD" "$VG_NAME"

    read -r -p "请输入逻辑卷名称 [默认: data]: " LV_NAME
    LV_NAME="${LV_NAME:-data}"
    lv_path="/dev/$VG_NAME/$LV_NAME"

    if lvdisplay "$lv_path" >/dev/null 2>&1; then
        read -r -p "逻辑卷 $lv_path 已存在，是否使用新空间扩容? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            extend_existing_lv "$lv_path"
        else
            die "用户取消操作"
        fi
    else
        info "正在创建逻辑卷 $lv_path..."
        run lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME"

        info "正在格式化 $lv_path 为 $FS_TYPE..."
        if [ "$FS_TYPE" = "xfs" ]; then
            run mkfs.xfs -f "$lv_path"
        else
            run mkfs.ext4 -F "$lv_path"
        fi
    fi

    prepare_mount_point
    if ! mountpoint -q "$MOUNT_POINT"; then
        run mount "$lv_path" "$MOUNT_POINT"
    fi
    fstab_add_once "$lv_path" "$MOUNT_POINT" "$FS_TYPE"
}

main() {
    require_root
    detect_os
    ask_mode
    ask_fs_type
    ensure_tools
    list_disks
    ask_disk
    ask_mount_point

    if [ "$MODE" = "partition" ]; then
        mount_partition_mode
    else
        mount_lvm_mode
    fi

    run chmod 755 "$MOUNT_POINT"
    success "硬盘挂载完成: $MOUNT_POINT"
    df -Th "$MOUNT_POINT"
}

main "$@"
