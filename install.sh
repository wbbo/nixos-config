#!/usr/bin/env bash
# NixOS 安装脚本 —— 手工分区 + nixos-install
# 用法: sudo ./install.sh --disk /dev/sdb [-f]
#       sudo ./install.sh -d /dev/nvme0n1 -f
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
die()   { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }

SCRIPT_NAME="$(basename "$0")"

help() {
  cat >&2 <<EOF
  NixOS 安装脚本 —— 手工分区 + nixos-install

用法:
  ${SCRIPT_NAME} --disk /dev/xxx [-f]

选项:
  -d, --disk <设备>    目标磁盘设备 (必需)
  -f, --force            静默安装, 跳过确认
  -h, --help             帮助

示例:
  sudo ${SCRIPT_NAME} --disk /dev/sda
  sudo ${SCRIPT_NAME} -d /dev/nvme0n1 -f

注: 内核模块/CPU 微码由 nixos-generate-config 自动检测。

EOF
  exit 0
}

FORCE=0; DISK=""

if ! TEMP=$(getopt -o d:fh --long disk:,force,help -n "$SCRIPT_NAME" -- "$@"); then
  echo "参数解析错误" >&2; exit 1
fi
eval set -- "$TEMP"

while true; do
  case "$1" in
    -d|--disk) DISK="$2"; shift 2 ;;
    -f|--force) FORCE=1; shift ;;
    -h|--help) help ;;
    --) shift; break ;;
    *) echo "未知选项: $1" >&2; help ;;
  esac
done

# 允许位置参数作为磁盘设备的快捷方式
REMAINING_ARGS=("$@")
if [ -z "$DISK" ] && [ ${#REMAINING_ARGS[@]} -gt 0 ]; then
  DISK="${REMAINING_ARGS[0]}"
  [ ${#REMAINING_ARGS[@]} -gt 1 ] && warn "多余的参数将被忽略, 仅使用 $DISK"
fi

[ -n "$DISK" ] || help
[ -b "$DISK" ] || die "磁盘 $DISK 不存在"
[ "$(id -u)" = 0 ] || die "请用 sudo 运行"

# 解析真实设备名 (处理 /dev/disk/by-id 等符号链接)
REAL_DISK=$(readlink -f "$DISK" 2>/dev/null || echo "$DISK")

echo ""
warn "即将清空 $DISK 全盘数据!"
lsblk -o NAME,SIZE,TRAN,MODEL "$REAL_DISK"
echo ""
if [ "$FORCE" -eq 1 ]; then
  warn "静默模式 (-f): 跳过确认"
else
  read -r -p "输入 yes 确认: " confirm
  [ "$confirm" = "yes" ] || { info "已取消"; exit 0; }
fi

# ============================================================================
# 阶段 0: 环境准备
# ============================================================================
info "[0/3] 环境检查"
MEM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}' 2>/dev/null || echo 4096)
info "可用内存: ${MEM_MB}M"

if [ "$MEM_MB" -lt 7680 ]; then
  warn "内存不足 8G, 创建临时 zram"
  if modprobe zram 2>/dev/null; then
    [ -e /dev/zram0 ] && { swapoff /dev/zram0 2>/dev/null || true; echo 1 > /sys/block/zram0/reset 2>/dev/null || true; }
    [ -e /sys/block/zram0/disksize ] && { echo 2G > /sys/block/zram0/disksize 2>/dev/null || true; }
    mkswap /dev/zram0 2>/dev/null && swapon /dev/zram0 && info "zram swap 已启用 (2G)" || warn "zram 启用失败, 继续安装"
  else
    warn "zram 模块加载失败, 继续安装"
  fi
fi

ROOT_FSTYPE=$(findmnt -no FSTYPE / 2>/dev/null)
if [ "$ROOT_FSTYPE" = "tmpfs" ]; then
  TMPFS_SIZE_G=$((MEM_MB * 2 / 1024))
  [ "$TMPFS_SIZE_G" -lt 8 ] && TMPFS_SIZE_G=8
  [ "$TMPFS_SIZE_G" -gt 16 ] && TMPFS_SIZE_G=16
  mount -o remount,size="${TMPFS_SIZE_G}G" / 2>/dev/null && info "tmpfs 扩容至 ${TMPFS_SIZE_G}G" \
    || warn "tmpfs 扩容失败, 安装可能出现空间不足"
  nix-collect-garbage 2>/dev/null || true
fi

# ============================================================================
# 阶段 1: 分区 & 格式化
# ============================================================================
info "[1/3] 分区: 格式化 $DISK 并挂载到 /mnt"

case "$REAL_DISK" in
  *nvme*|*NVME*)             PART_SUFFIX="p" ;;
  *mmcblk*|*MMCBLK*)         PART_SUFFIX="p" ;;
  *)                         PART_SUFFIX="" ;;
esac
ESP="${REAL_DISK}${PART_SUFFIX}1"
ROOT="${REAL_DISK}${PART_SUFFIX}2"

# ---- 步骤 1: 清理旧分区 ----
info "清理 $DISK 已有的分区"
umount -R /mnt 2>/dev/null || true

# 使用 glob 匹配分区: /dev/sda[0-9]* 精确匹配数字后缀, 避免误伤 sdaa
PART_GLOB="${REAL_DISK}${PART_SUFFIX}[0-9]*"
for part_dev in $PART_GLOB; do
  [ -b "$part_dev" ] || continue
  swapoff "$part_dev" 2>/dev/null || true
  umount -fl "$part_dev" 2>/dev/null || true
  wipefs -a "$part_dev" 2>/dev/null || true
done

# 通知内核删除旧分区 (BLKPG_DEL_PARTITION ioctl)
partx -d "$REAL_DISK" 2>/dev/null || true
# 让 btrfs 内核扫描器忘记设备
btrfs device scan --forget 2>/dev/null || true
udevadm settle 2>/dev/null || true

# ---- 步骤 2: dd 清零 GPT 头尾 + 旧 btrfs 超级块 ----
dd if=/dev/zero of="$REAL_DISK" bs=1M count=1  2>/dev/null || true
dd if=/dev/zero of="$REAL_DISK" bs=1M seek=1024 count=10 2>/dev/null || true
SECTOR_SIZE=$(blockdev --getss "$REAL_DISK" 2>/dev/null || echo 512)
DISK_SZ=$(blockdev --getsz "$REAL_DISK" 2>/dev/null || echo 0)
if [ "$DISK_SZ" -gt 2048 ] 2>/dev/null; then
  dd if=/dev/zero of="$REAL_DISK" bs="$SECTOR_SIZE" seek="$((DISK_SZ - 2048))" count=2048 2>/dev/null || true
fi
# 清除元数据后再次让 btrfs 忘记
btrfs device scan --forget 2>/dev/null || true
udevadm settle 2>/dev/null || true

# ---- 步骤 3: 尝试 parted 写入新 GPT ----
# 重复安装时 btrfs 内核模块可能持有旧设备引用导致 BLKRRPART 失败,
# 输出错误信息方便诊断, 用户可以 reboot 后重试。
parted_output=$(parted -s "$REAL_DISK" mklabel gpt 2>&1) || true
if echo "$parted_output" | grep -qi "Device or resource busy\|being used\|in use"; then
  die "磁盘 $DISK 被占用 (内核持有旧分区引用)。请 reboot 后重试。"
fi
parted -s "$REAL_DISK" mkpart primary fat32 1M 1G 2>&1 || true
parted -s "$REAL_DISK" set 1 esp on 2>&1 || true
parted -s "$REAL_DISK" mkpart primary btrfs 1G 100% 2>&1 || true

# ---- 步骤 4: 创建分区设备节点 ----
partx -a "$REAL_DISK" 2>/dev/null || partprobe "$REAL_DISK" 2>/dev/null || true
udevadm settle 2>/dev/null || true

# ---- 步骤 5: 等待设备节点就绪 ----
for i in $(seq 1 20); do
  [ -b "$ESP" ] && [ -b "$ROOT" ] && break
  sleep 0.5
done
[ -b "$ESP"  ] || die "分区 $ESP 未就绪。内核可能持有旧分区引用, 请 reboot 后重试。"
[ -b "$ROOT" ] || die "分区 $ROOT 未就绪。内核可能持有旧分区引用, 请 reboot 后重试。"

# ---- 步骤 6: 格式化前最终防护 ----
umount -R /mnt 2>/dev/null || true
umount -fl "$ESP" 2>/dev/null || true
umount -fl "$ROOT" 2>/dev/null || true
btrfs device scan --forget 2>/dev/null || true
udevadm settle 2>/dev/null || true

# ---- 步骤 7: 格式化 ----
mkfs.vfat -n ESP -F 32 "$ESP" || die "无法格式化 $ESP (设备可能被占用, 请 reboot 后重试)"
mkfs.btrfs -f -L nixos "$ROOT" || die "无法格式化 $ROOT (设备可能被占用, 请 reboot 后重试)"

# ---- 步骤 8: 创建子卷并挂载 ----
mount -t btrfs -o compress=zstd:3,noatime "$ROOT" /mnt
for vol in @root @nix @persist @swap @snapshots; do
  btrfs subvolume create "/mnt/$vol"
done
umount /mnt

mount -t btrfs -o compress=zstd:3,noatime,subvol=@root "$ROOT" /mnt
mkdir -p /mnt/{boot,nix,persist,swap,.snapshots}
mount -t btrfs -o compress=zstd:3,noatime,subvol=@nix "$ROOT" /mnt/nix
mount -t btrfs -o compress=zstd:3,noatime,subvol=@persist "$ROOT" /mnt/persist
mount -t btrfs -o noatime,subvol=@swap "$ROOT" /mnt/swap
mount -t btrfs -o noatime,subvol=@snapshots "$ROOT" /mnt/.snapshots
mount "$ESP" /mnt/boot

# ---- 步骤 9: btrfs swapfile ----
touch /mnt/swap/swapfile
chmod 0600 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile 2>/dev/null || true
# fallocate 在 nodatacow 文件上会失败, dd 作为可靠回退, 使用较大块加速
fallocate -l 16G /mnt/swap/swapfile 2>/dev/null || \
  dd if=/dev/zero of=/mnt/swap/swapfile bs=16M count=1024 conv=fdatasync status=none 2>/dev/null || true
mkswap /mnt/swap/swapfile || die "无法创建 swap"

mountpoint -q /mnt     || die "挂载失败: /mnt"
mountpoint -q /mnt/nix || die "挂载失败: /mnt/nix"
info "磁盘已分区并挂载到 /mnt"

# ============================================================================
# 阶段 1.5: hardware-configuration.nix
# ============================================================================
info "[1.5/3] 检测硬件: 生成 hardware-configuration.nix"
nixos-generate-config --root /mnt 2>/dev/null || true
if [ -f /mnt/etc/nixos/hardware-configuration.nix ]; then
  cp /mnt/etc/nixos/hardware-configuration.nix hosts/wbb/ || die "无法复制 hardware-configuration.nix 到 hosts/wbb/"
  info "hardware-configuration.nix 已生成到 hosts/wbb/"
else
  warn "nixos-generate-config 失败, 使用默认硬件配置"
  ROOT_UUID=$(blkid -s UUID -o value "$ROOT" || true)
  ESP_UUID=$(blkid -s UUID -o value "$ESP" || true)
  [ -n "$ROOT_UUID" ] || die "无法获取 $ROOT 的 UUID"
  [ -n "$ESP_UUID"  ] || die "无法获取 $ESP 的 UUID"
  cat > hosts/wbb/hardware-configuration.nix <<HWEOF
# 硬件配置 —— 由 install.sh fallback 自动生成
{ config, lib, pkgs, modulesPath, ... }:
{
  boot.initrd.availableKernelModules = [
    "ahci" "nvme" "sd_mod" "usb_storage" "usbhid" "uas"
    "xhci_pci" "ehci_pci" "iwlwifi" "iwlmvm" "iwldvm"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.cpu.intel.updateMicrocode = true;

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType = "btrfs";
    options = [ "subvol=@root" "compress=zstd:3" "noatime" ];
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/${ESP_UUID}";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };
  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd:3" "noatime" ];
  };
  fileSystems."/persist" = {
    device = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType = "btrfs";
    options = [ "subvol=@persist" "compress=zstd:3" "noatime" ];
  };
  fileSystems."/swap" = {
    device = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType = "btrfs";
    options = [ "subvol=@swap" "noatime" ];
  };
  fileSystems."/.snapshots" = {
    device = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType = "btrfs";
    options = [ "subvol=@snapshots" "noatime" ];
  };
  swapDevices = [ { device = "/swap/swapfile"; } ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
HWEOF
fi

# ---- 阶段 1.6: git commit (nixos-install --flake 仅读取 git 追踪文件) ----
# nixos-install 通过 git+file:// 读取 flake, 必须确保 hardware-configuration.nix
# 和 flake.lock 都已 commit, 否则构建时报 "path does not exist" 或 "not tracked by Git"。
# 注意: NixOS Live ISO 可能未配置 git user.{name,email}, 需通过 -c 临时覆盖。
if [ -d "$SCRIPT_DIR/.git" ]; then
  # 修复 git index 所有者问题: rsync 作为 root 运行后 index 属主可能不是 repo 属主
  [ -f "$SCRIPT_DIR/.git/index" ] && [ "$(stat -c %u "$SCRIPT_DIR/.git/index" 2>/dev/null)" != "$(id -u 2>/dev/null)" ] && \
    rm -f "$SCRIPT_DIR/.git/index" && git -C "$SCRIPT_DIR" reset HEAD 2>/dev/null || true
  git -C "$SCRIPT_DIR" add hosts/wbb/hardware-configuration.nix flake.lock 2>/dev/null || true
  if git -C "$SCRIPT_DIR" \
    -c user.email="install@nixos.local" \
    -c user.name="NixOS Installer" \
    commit -m "install: hardware-configuration for $(hostname)" 2>/dev/null; then
    info "hardware-configuration.nix 已提交到 git"
  else
    warn "git commit 未执行 (可能已提交或无变更), 继续安装"
  fi
else
  die "$SCRIPT_DIR/.git 不存在, 无法 commit。请从 git clone 重新获取本仓库。"
fi

# 确保 git 允许当前用户访问 (libgit2 安全检查: 仓库所有者必须匹配)
git config --global --add safe.directory "$SCRIPT_DIR" 2>/dev/null || true

# ============================================================================
# 阶段 2: 启用 swap
# ============================================================================
info "[2/3] 启用 swap"
SWAPFILE="/mnt/swap/swapfile"
swapon "$SWAPFILE" && info "磁盘 swapfile 已启用 (16G)" || warn "swapfile 启用失败, 继续安装"
info "总 swap: $(free -m | awk '/Swap:/{print $2}')M"

# ============================================================================
# 阶段 3: nixos-install
# ============================================================================
info "[3/3] nixos-install: 安装 NixOS (请耐心等待)"
nixos-install --flake .#wbb --no-channel-copy --no-root-password --max-jobs 1 --cores 1

swapoff "$SWAPFILE" 2>/dev/null || true
swapoff /dev/zram0 2>/dev/null || true

echo ""; info "安装完成!"; echo ""
echo "下一步:"
echo "  nixos-enter --root /mnt -c 'passwd root'"
echo "  reboot"
echo ""
echo "首次启动后:"
echo "  passwd wbb"
