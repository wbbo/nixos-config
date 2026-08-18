#!/usr/bin/env bash
# NixOS 安装脚本 —— disko 分区 + nixos-install
# 用法: sudo ./install.sh --disk /dev/sdb [-f]
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
  NixOS 安装脚本 —— disko 分区 + nixos-install

用法:
  ${SCRIPT_NAME} --disk /dev/xxx [-f]

选项:
  -d, --disk <设备>       目标磁盘设备 (必需)
  -f, --force              静默模式, 跳过磁盘确认 (自动 wipe)
  -h, --help               帮助

示例:
  # 全新安装 (最简: 只需选磁盘)
  sudo ${SCRIPT_NAME} -d /dev/sda

  # 静默安装 (无人值守)
  sudo ${SCRIPT_NAME} -d /dev/sda -f

  # 携带 GitHub token (可选, 避免匿名限流 403)
  sudo env GITHUB_TOKEN=ghp_xxx ${SCRIPT_NAME} -d /dev/sda

分区由 disko 声明式管理。主机名/主机目录自动从 flake.nix 读取,
用户名/主机名可在 hosts/<hostDir>/local.nix 覆盖, secrets 安装后初始化 (见 README)。
EOF

  exit "${1:-0}"
}

FORCE=0; DISK=""

# 主机名/主机目录自动从 flake.nix 读取 (networking.hostName 可在 local.nix 覆盖)
HOST_NAME="$(grep -oP 'hostName = "\K[^"]+' "$SCRIPT_DIR/flake.nix" 2>/dev/null | head -1)"
HOST_NAME="${HOST_NAME:-nixos}"
HOST_DIR="$(grep -oP 'hostDir = "\K[^"]+' "$SCRIPT_DIR/flake.nix" 2>/dev/null | head -1)"
HOST_DIR="${HOST_DIR:-default}"

if ! TEMP=$(getopt -o d:fh --long disk:,force,help -n "$SCRIPT_NAME" -- "$@"); then
  echo "参数解析错误" >&2; exit 1
fi
eval set -- "$TEMP"

while true; do
  case "$1" in
    -d|--disk) DISK="$2"; shift 2 ;;
    -f|--force) FORCE=1; shift ;;
    -h|--help) help 0 ;;
    --) shift; break ;;
    *) echo "未知选项: $1" >&2; help 1 ;;
  esac
done

# 允许位置参数作为磁盘设备的快捷方式
REMAINING_ARGS=("$@")
if [ -z "$DISK" ] && [ ${#REMAINING_ARGS[@]} -gt 0 ]; then
  DISK="${REMAINING_ARGS[0]}"
  [ ${#REMAINING_ARGS[@]} -gt 1 ] && warn "多余的参数将被忽略, 仅使用 $DISK"
fi

[ -n "$DISK" ] || help 1
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
# 阶段 1: 环境准备
# ============================================================================
info "[1/4] 环境检查"
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
fi

# ---- GitHub token (可选): 安装期给 Live CD 的 nix 提供凭据 ----
# sudo 默认清空环境变量, 需 `sudo env GITHUB_TOKEN=ghp_xxx ./install.sh ...` 传入。
# access-tokens 一项即可: 分支解析与 tarball 下载均带 token 头 (fetcher 有凭据时
# 统一走 api.github.com, 5000 次/h; 无凭据则回退匿名直链, 60 次/h)。
# 凭据只活在 Live CD (tmpfs, 重启即焚); 常驻凭据装好后走 secrets.yaml (sops-nix)。
if [ -n "${GITHUB_TOKEN:-}" ]; then
  # 追加而非覆盖, 保留调用者已有的 NIX_CONFIG; 作用于脚本内全部 nix 调用
  NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}access-tokens = github.com=$GITHUB_TOKEN"
  export NIX_CONFIG
  unset GITHUB_TOKEN   # 子进程统一经 NIX_CONFIG 获取, 避免多渠道泄漏
  info "GitHub token 已启用 (access-tokens)"
fi

# ============================================================================
# 阶段 2: disko 分区 & 格式化 & 挂载
# ============================================================================
info "[2/4] 分区: disko 格式化 $DISK 并挂载到 /mnt"

# 清理残留挂载 (上次安装失败或中断可能留下)
# 只关磁盘 swap, 保留阶段 1 创建的 zram (内存 <8G 防编译 OOM)
for sw in $(swapon --show=NAME --noheadings 2>/dev/null | grep -v -E '^/dev/zram'); do
  swapoff "$sw" 2>/dev/null || true
done
umount -R /mnt 2>/dev/null || true
# 用实际设备路径替换 disks.nix 中的占位符
DISKO_CFG="$SCRIPT_DIR/hosts/${HOST_DIR}/disks.nix"
if ! grep -q 'DISK_DEVICE_PLACEHOLDER' "$DISKO_CFG"; then
  die "disks.nix 缺少 DISK_DEVICE_PLACEHOLDER 占位符, 请检查配置"
fi
# 在临时副本中替换, 确保原文件不受影响
DISKO_TMP="$(mktemp -t disko.XXXXXX.nix)"
sed "s|DISK_DEVICE_PLACEHOLDER|$REAL_DISK|g" "$DISKO_CFG" > "$DISKO_TMP"
trap 'rm -f "$DISKO_TMP"' EXIT

# disko --mode zap_create_mount: 等效 destroy + format + mount, 一步完成
DISKO_FLAGS=(--mode zap_create_mount)
if [ "$FORCE" -eq 1 ]; then
  DISKO_FLAGS+=(--yes-wipe-all-disks)
fi
# --root-mountpoint 指向 /mnt (disko 在该路径下执行挂载)
# 用 flake 锁定的 disko 包 (flake.nix 导出 inputs.disko): 避免拉 master 触发
# GitHub API 匿名限流 403 (已修复过的回归), 且与 nixos-install 构建用的锁定版本一致。
nix --extra-experimental-features "nix-command flakes" \
  run "$SCRIPT_DIR#disko" -- "${DISKO_FLAGS[@]}" --root-mountpoint /mnt "$DISKO_TMP" \
  || die "disko 分区失败。请检查磁盘是否被占用 (reboot 后重试)。"

mountpoint -q /mnt     || die "挂载失败: /mnt"
mountpoint -q /mnt/nix || die "挂载失败: /mnt/nix"
info "磁盘已分区并挂载到 /mnt (disko)"

rm -f "$DISKO_TMP"

# ============================================================================
# 阶段 2.5: hardware-configuration.nix
# ============================================================================
info "[2.5/4] 检测硬件: 生成 hardware-configuration.nix"

# 从 nixos-generate-config 提取硬件检测结果 (initrd/kernel 模块 + CPU 微码),
# fileSystems / swapDevices 由 disko 模块根据 disks.nix 自动生成, 无需在此定义。
nixos-generate-config --root /mnt 2>/dev/null || true
HW_NIX="/mnt/etc/nixos/hardware-configuration.nix"
if [ -f "$HW_NIX" ]; then
  # 使用 awk 解析提取 [ ... ] 之间的内核模块名称。
  # 兼容 nixos-generate-config 的两种输出格式:
  #   - 多行:  boot.initrd.availableKernelModules = [\n    "m1" "m2"\n  ];
  #   - 单行:  boot.initrd.availableKernelModules = [ "m1" "m2" ];
  INITRD_MODS=$(awk '
    /boot\.initrd\.availableKernelModules/ {
      sub(/^[[:space:]]*boot\.initrd\.availableKernelModules[[:space:]]*=[[:space:]]*\[[[:space:]]*/, "")
      if ($0 ~ /\];/) {
        sub(/[[:space:]]*\];.*/, "")
        print
        exit
      }
      printf "%s\n", $0
      while (getline > 0) {
        if ($0 ~ /^[[:space:]]*\];/) exit
        print
      }
      exit
    }
  ' "$HW_NIX")
  # 如果提取失败或为空, 使用默认模块列表
  if [ -z "$INITRD_MODS" ]; then
    warn "无法从 hardware-configuration.nix 提取内核模块, 使用默认值"
    INITRD_MODS='"ahci" "nvme" "sd_mod" "usb_storage" "usbhid" "uas"
      "xhci_pci" "ehci_pci" "iwlwifi" "iwlmvm" "iwldvm"'
  fi
  # 提取 boot.kernelModules (不含 initrd, 精确匹配行首)
  KERNEL_MODS=$(grep -E '^[[:space:]]*boot\.kernelModules[[:space:]]*=' "$HW_NIX" 2>/dev/null \
    || echo '  boot.kernelModules = [ ];')
  # 用 /proc/cpuinfo 检测 CPU 厂商 (nixos-generate-config 的微码行是
  # lib.mkDefault config.hardware.enableRedistributableFirmware, 无字面 true, 不能 grep)
  HAS_INTEL=$(grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null && echo true || echo false)
  HAS_AMD=$(grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null && echo true || echo false)
else
  warn "nixos-generate-config 失败, 使用默认硬件检测"
  INITRD_MODS='"ahci" "nvme" "sd_mod" "usb_storage" "usbhid" "uas"
    "xhci_pci" "ehci_pci" "iwlwifi" "iwlmvm" "iwldvm"'
  KERNEL_MODS='  boot.kernelModules = [ ];'
  HAS_INTEL=$(grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null && echo true || echo false)
  HAS_AMD=$(grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null && echo true || echo false)
fi

# ---- 从 disks.nix 提取文件系统, 写入 supportedFilesystems ----
# 解析 disks.nix 中的 format / type 字段, 提取全部文件系统
# 每行一个 (printf 换行) 让 sort -u 按行去重, 且保留双引号 (Nix 列表需要字符串字面量)
DISKO_FS="$(awk '/format =|type =.*"(btrfs|ext4|xfs|f2fs|vfat|ntfs|zfs|tmpfs|exfat)"/ { gsub(/[";]/,"",$3); printf "\"%s\"\n", $3 }' "$DISKO_CFG" | sort -u | tr '\n' ' ')"

info "检测到文件系统: ${DISKO_FS}"

mkdir -p "hosts/${HOST_DIR}"
cat > hosts/${HOST_DIR}/hardware-configuration.nix <<HWEOF
# 硬件配置 —— 由 install.sh 自动生成
{ lib, modulesPath, ... }:
{
  # 文件系统支持 —— 从 hosts/${HOST_DIR}/disks.nix 自动推导
  boot.initrd.supportedFilesystems = [ ${DISKO_FS} ];
  boot.initrd.availableKernelModules = [
${INITRD_MODS}
  ];
${KERNEL_MODS}
  hardware.cpu.intel.updateMicrocode = ${HAS_INTEL};
  hardware.cpu.amd.updateMicrocode = ${HAS_AMD};

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
HWEOF

info "hardware-configuration.nix 已生成到 hosts/${HOST_DIR}/"

# ---- 阶段 2.6: git commit (nixos-install --flake 仅读取 git 追踪文件) ----
# nixos-install 通过 git+file:// 读取 flake, 必须确保所有文件都已 git add,
# 否则构建时报 "path not tracked by Git"。
# 注意: NixOS Live ISO 可能未配置 git user.{name,email}, 需通过 -c 临时覆盖。
if [ -d "$SCRIPT_DIR/.git" ]; then
  # git 安全检查: 仓库所有者必须匹配当前用户 (libgit2 / git CLI 均要求)
  git config --global --add safe.directory "$SCRIPT_DIR" 2>/dev/null || true

  # 修复 git index 属主问题
  if [ -f "$SCRIPT_DIR/.git/index" ] && [ "$(stat -c %u "$SCRIPT_DIR/.git/index" 2>/dev/null)" != "$(id -u 2>/dev/null)" ]; then
    chown "$(id -u):$(id -g)" "$SCRIPT_DIR/.git/index" 2>/dev/null || rm -f "$SCRIPT_DIR/.git/index"
  fi

  # git add -f: 逐个追加所有必需文件, -f 绕过 .gitignore
  # (比 add -A 更可靠: 不依赖 index 状态, live ISO 上 index 经常损坏)
  git -C "$SCRIPT_DIR" add -f hosts/${HOST_DIR}/hardware-configuration.nix 2>/dev/null || true
  git -C "$SCRIPT_DIR" add -f flake.nix flake.lock hosts/ modules/ secrets/ .sops.yaml 2>/dev/null || true

  # 关键验证: hardware-configuration.nix 必须在 index 中, 否则 nixos-install 必然失败
  if ! git -C "$SCRIPT_DIR" ls-files --error-unmatch hosts/${HOST_DIR}/hardware-configuration.nix >/dev/null 2>&1; then
    die "hardware-configuration.nix 未能添加到 git, 无法继续安装"
  fi

  # 有暂存变更才 commit: 重装同机时 hardware-configuration.nix 与已有记录
  # 可能完全一致 (git commit 会报 nothing to commit), 此时跳过继续安装
  if git -C "$SCRIPT_DIR" diff --cached --quiet; then
    info "无暂存变更, 跳过 git commit (hardware-configuration.nix 与已记录内容一致)"
  elif git -C "$SCRIPT_DIR" \
    -c user.email="install@nixos.local" \
    -c user.name="NixOS Installer" \
    commit -m "install: hardware-configuration for $(hostname)"; then
    info "所有文件已提交到 git (含 hardware-configuration.nix)"
  else
    die "git commit 失败, 无法继续。请检查: git -C $SCRIPT_DIR status"
  fi
else
  die "$SCRIPT_DIR/.git 不存在, 无法 commit。请从 git clone 重新获取本仓库。"
fi

# ============================================================================
# 阶段 3: 启用 swap
# ============================================================================
info "[3/4] 启用 swap"
SWAPFILE="/mnt/swap/swapfile"
if [ -f "$SWAPFILE" ]; then
  swapon "$SWAPFILE" && info "磁盘 swapfile 已启用 (16G)" || warn "swapfile 启用失败, 继续安装"
else
  warn "swapfile 不存在 ($SWAPFILE), disko 可能未创建, 继续安装"
fi
info "总 swap: $(free -m | awk '/Swap:/{print $2}')M"

# ============================================================================
# 阶段 4: nixos-install
# ============================================================================
info "[4/4] nixos-install: 安装 NixOS (请耐心等待)"
# 设置 GOPROXY 使用国内镜像, 避免 proxy.golang.org 超时导致 sops-install-secrets 编译失败
export GOPROXY="https://goproxy.cn,direct"

# nixos-install 默认会生成 /mnt/etc/nixos/configuration.nix 模板文件
# 该文件干扰后续 nixos-rebuild switch (flake 优先读取 /etc/nixos)
# 将其删除, 确保系统只使用 flake 配置
rm -f /mnt/etc/nixos/configuration.nix 2>/dev/null || true
rm -f /mnt/etc/NIXOS 2>/dev/null || true

# ---- host key 固化: nixos-install 前放入 chroot (secrets 解密一致性) ----
# nixos-install 的 activation 阶段 sops-install-secrets 即需读取 chroot 的
# /etc/ssh/ssh_host_ed25519_key 派生 age 密钥解密 secrets (secrets.nix 的
# sops.age.sshKeyPaths)。全新格式化的盘上此刻尚无 host key, 不提前放入则
# 安装期解密必失败 (Cannot read ssh key / 0 successful groups); 固化后的
# key 在首启时被 sshd 复用, 与 secrets 加密公钥保持一致。
# 重装/换盘场景: 先在 Live CD 上恢复旧 host key 到 /etc/ssh/ 再运行本脚本。
if [ -f /etc/ssh/ssh_host_ed25519_key ]; then
  info "固化 SSH host key 到目标系统 (secrets 解密一致性)"
  mkdir -p /mnt/etc/ssh
  cp -a /etc/ssh/ssh_host_ed25519_key* /mnt/etc/ssh/ 2>/dev/null \
    || warn "host key 复制失败, 新系统将重新生成 (需重启后重新初始化 secrets)"
  # rsa key 一并固化 (若存在), 消除 sops-install-secrets 扫描 rsa 的噪音警告
  cp -a /etc/ssh/ssh_host_rsa_key* /mnt/etc/ssh/ 2>/dev/null || true
else
  warn "Live CD 无 /etc/ssh/ssh_host_ed25519_key (重装/换盘应先恢复旧 key)"
  warn "安装期 sops 解密将失败; 重启后需按 README 初始化 secrets (host key 公钥 + 模板)"
fi

nixos-install --flake ".#${HOST_NAME}" --no-channel-copy --no-root-password

swapoff "$SWAPFILE" 2>/dev/null || true
swapoff /dev/zram0 2>/dev/null || true

echo ""; info "安装完成!"; echo ""
if [ -f /mnt/etc/ssh/ssh_host_ed25519_key ]; then
  echo "> SSH host key 已固化到目标系统, 安装期 secrets 解密应已成功。"
else
  echo "> SSH host key 未固化 (Live CD 上无 host key), 安装期 sops 解密已失败。"
  echo "   重启后需按 README 初始化 secrets (host key 公钥 + secrets 模板) 再 rebuild。"
fi
echo ""
echo "下一步:"
echo "  reboot"
echo ""
echo "重启后: 确认 /run/secrets 正常解密, 并按需配置 hosts/${HOST_DIR}/local.nix (用户名/主机名)。"
