#!/bin/bash
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 异常处理函数
cleanup() {
  echo -e "${RED}发生错误，执行清理...${NC}"
  [ -n "$VG_CREATED" ] && vgremove -f "$VG_NAME" >/dev/null 2>&1 || true
  [ -n "$PV_CREATED" ] && pvremove -f "$DISK_ADD" >/dev/null 2>&1 || true
  exit 1
}

trap cleanup ERR

# 显示可用磁盘函数
list_available_disks() {
  echo -e "${YELLOW}可用磁盘列表：${NC}"
  lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | awk '
    NR==1 {print "  设备\t大小\t类型\t挂载点"; next}
    $3=="disk" && $4=="" {print "  /dev/"$1"\t"$2"\t"$3"\t"$4}
  ' | column -t
  
  echo
  read -p "请选择要使用的磁盘设备路径 (例如/dev/sdb): " DISK_ADD
  
  # 验证磁盘存在且未挂载
  [ -b "$DISK_ADD" ] || { echo -e "${RED}错误：设备 $DISK_ADD 不存在${NC}"; exit 1; }
  mount | grep -q "$DISK_ADD" && { echo -e "${RED}错误：设备 $DISK_ADD 已挂载${NC}"; exit 1; }
}

# 选择文件系统类型
select_filesystem() {
  PS3="请选择文件系统类型 (默认xfs): "
  select FS_TYPE in xfs ext4 btrfs; do
    FS_TYPE=${FS_TYPE:-xfs}
    case $FS_TYPE in
      xfs|ext4|btrfs) break ;;
      *) echo -e "${RED}无效选择，请重新输入${NC}" ;;
    esac
  done
}

# 选择或创建卷组
handle_vg() {
  local existing_vgs=$(vgs --noheadings -o vg_name | tr -d ' ')
  
  if [ -n "$existing_vgs" ]; then
    PS3="请选择要扩展的卷组 (输入数字) 或选择创建新卷组: "
    select VG_NAME in $existing_vgs "创建新卷组"; do
      [ -n "$VG_NAME" ] || { echo -e "${RED}无效选择${NC}"; continue; }
      
      if [ "$VG_NAME" == "创建新卷组" ]; then
        read -p "请输入新卷组名称: " VG_NAME
        vgcreate "$VG_NAME" "$DISK_ADD" && VG_CREATED=true
      else
        vgextend "$VG_NAME" "$DISK_ADD"
      fi
      break
    done
  else
    read -p "没有现有卷组，请输入新卷组名称: " VG_NAME
    vgcreate "$VG_NAME" "$DISK_ADD" && VG_CREATED=true
  fi
}

main() {
  echo -e "${GREEN}\n=== 磁盘初始化与挂载工具 ===${NC}"
  
  # 步骤1: 选择磁盘
  list_available_disks
  
  # 步骤2: 创建物理卷
  echo -e "${YELLOW}正在创建物理卷...${NC}"
  pvcreate -f "$DISK_ADD" && PV_CREATED=true
  
  # 步骤3: 处理卷组
  handle_vg
  
  # 步骤4: 创建逻辑卷
  echo -e "${YELLOW}正在创建逻辑卷...${NC}"
  lvcreate -l 100%FREE -n data "$VG_NAME"
  
  # 步骤5: 选择文件系统
  select_filesystem
  
  # 步骤6: 创建文件系统
  echo -e "${YELLOW}正在创建$FS_TYPE文件系统...${NC}"
  mkfs."$FS_TYPE" -f "/dev/$VG_NAME/data"
  
  # 步骤7: 挂载分区
  [ -d /data ] || mkdir -p /data
  mount "/dev/$VG_NAME/data" /data
  
  # 步骤8: 持久化挂载
  echo "/dev/$VG_NAME/data /data $FS_TYPE defaults 0 0" >> /etc/fstab
  
  # 显示结果
  echo -e "${GREEN}\n操作成功完成！${NC}"
  df -hT /data
  echo -e "\n当前卷组状态："
  vgs
}

main
