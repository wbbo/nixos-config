#!/usr/bin/env bash
# NixOS 安装脚本 —— disko 分区 + nixos-install
# 用法: sudo ./install.sh --disk /dev/sdb [-k AGE-SECRET-KEY] [-t GITHUB_TOKEN] [-u GITHUB_USER] [-p PASSWORD_HASH] [-f]
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
  ${SCRIPT_NAME} --disk /dev/xxx [-k AGE-SECRET-KEY] [-t GITHUB_TOKEN] [-u GITHUB_USER] [-p PASSWORD_HASH] [-f]

选项:
  -d, --disk <设备>       目标磁盘设备 (必需)
  -k, --age-key <密钥>     sops-nix age 私钥 (可选: 未提供则自动生成密钥对)
  -t, --token <token>      GitHub personal access token (可选: 空权限只读公开仓库)
  -u, --user <用户名>       GitHub 用户名 (配合 -t 使用, 默认 wbb)
  -p, --pass-hash <哈希>   用户密码哈希 (可选: 未提供则交互式设置密码)
  -f, --force              静默安装, 跳过所有确认 (需提供 -p, 否则自动生成密钥)
  -h, --help               帮助

示例:
  # 全新安装 (最简: 只需选磁盘, 其余全自动)
  sudo ${SCRIPT_NAME} -d /dev/sda

  # 已有 age 私钥 (复用旧主机的 keys.txt)
  sudo ${SCRIPT_NAME} -d /dev/sda -k AGE-SECRET-KEY-1xxx

  # 全参数 (适合脚本化/无人值守)
  sudo ${SCRIPT_NAME} -d /dev/sda -f -k AGE-SECRET-KEY-1xxx -t ghp_xxx -p '\$y\$j9T\$...'

未传入 -k 时自动生成 age 密钥对并更新 .sops.yaml; 未传入 -p 时交互式设置密码。
分区由 disko 声明式管理, secrets 自动写入并 sops 加密。
EOF

  exit 0
}

FORCE=0; DISK=""; AGE_KEY_ARG=""; GITHUB_TOKEN_ARG=""; GITHUB_USER_ARG=""; PASS_HASH_ARG=""

if ! TEMP=$(getopt -o d:k:t:u:p:fh --long disk:,age-key:,token:,user:,pass-hash:,force,help -n "$SCRIPT_NAME" -- "$@"); then
  echo "参数解析错误" >&2; exit 1
fi
eval set -- "$TEMP"

while true; do
  case "$1" in
    -d|--disk) DISK="$2"; shift 2 ;;
    -k|--age-key) AGE_KEY_ARG="$2"; shift 2 ;;
    -t|--token) GITHUB_TOKEN_ARG="$2"; shift 2 ;;
    -u|--user) GITHUB_USER_ARG="$2"; shift 2 ;;
    -p|--pass-hash) PASS_HASH_ARG="$2"; shift 2 ;;
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
fi

# ============================================================================
# 阶段 0.5: sops-nix age 密钥
# ============================================================================
info "[0.5/3] sops-nix age 密钥检查"

# sops-nix 在 nixos-install 阶段从 /tmp/sops-age-key 读取 age 私钥解密 secrets。
# 密钥不在此脚本内存储——用户需在运行 install.sh 前手动提供。

# age 私钥格式: AGE-SECRET-KEY-1 开头, 后跟 base64 编码的随机字节。
# 来源: 已安装宿主机上 ~/.config/sops/age/keys.txt (首次由 age-keygen 生成)。
# 获取: 复制 keys.txt 中的 AGE-SECRET-KEY-1 行, 或直接 scp 该文件到 Live CD。

AGE_KEY_SRC="/tmp/sops-age-key"
AGE_KEY_DST="/mnt/root/.config/sops/age"

# 优先级: -k/--age-key 参数 > /tmp/sops-age-key 文件 > ~/.config/sops/age/keys.txt > 交互粘贴
if [ -n "$AGE_KEY_ARG" ]; then
  if printf '%s\n' "$AGE_KEY_ARG" | grep -qE '^AGE-SECRET-KEY-1'; then
    printf '%s\n' "$AGE_KEY_ARG" > "$AGE_KEY_SRC"
    chmod 600 "$AGE_KEY_SRC"
    info "age 密钥通过命令行参数 -k 传入"
  else
    die "-k 参数格式不正确, 应以 AGE-SECRET-KEY-1 开头"
  fi
elif [ -f "$AGE_KEY_SRC" ]; then
  info "发现 /tmp/sops-age-key, 将在安装后持久化到 /root/.config/sops/age/"
elif [ -f "$HOME/.config/sops/age/keys.txt" ]; then
  info "从 ~/.config/sops/age/keys.txt 读取 age 密钥"
  mkdir -p "$(dirname "$AGE_KEY_SRC")"
  cp "$HOME/.config/sops/age/keys.txt" "$AGE_KEY_SRC"
  chmod 600 "$AGE_KEY_SRC"
else
  warn "未找到 sops-nix age 私钥"
  echo ""

  if [ "$FORCE" -eq 1 ]; then
    info "静默模式: 自动生成 age 密钥对"
    AUTO_GEN=1
  else
    echo "  secrets/secrets.yaml 需要 age 私钥解密。你可以:"
    echo ""
    echo "    [G] 生成新密钥对 —— 首次安装 / 旧密钥已丢失（默认）"
    echo "    [P] 粘贴已有私钥 —— 从旧主机恢复"
    echo ""
    read -r -p "  选择 [G/p]: " choice
    case "${choice:-g}" in
      [gG]*) AUTO_GEN=1 ;;
      *) AUTO_GEN=0 ;;
    esac
  fi

  if [ "$AUTO_GEN" -eq 1 ]; then
    # 生成新密钥对
    KEY_DIR="$HOME/.config/sops/age"
    mkdir -p "$KEY_DIR"
    nix --extra-experimental-features "nix-command flakes" shell nixpkgs#age --command \
      age-keygen -o "$KEY_DIR/keys.txt"
    AGE_KEY_LINE="$(grep 'AGE-SECRET-KEY-1' "$KEY_DIR/keys.txt")"
    # 从私钥推导公钥
    PUB_KEY="$(printf '%s\n' "$AGE_KEY_LINE" | \
      nix --extra-experimental-features "nix-command flakes" shell nixpkgs#age --command age-keygen -y)"

    printf '%s\n' "$AGE_KEY_LINE" > "$AGE_KEY_SRC"
    chmod 600 "$AGE_KEY_SRC"
    info "age 密钥对已生成 → $KEY_DIR/keys.txt"
    echo "  ${GREEN}公钥:${NC} $PUB_KEY"
    echo "  ${GREEN}私钥:${NC} $AGE_KEY_LINE"
    echo ""
    echo "  ${YELLOW}⚠  请立即备份私钥到密码管理器! 丢失后无法恢复 secrets。${NC}"
    echo ""

    # 更新 .sops.yaml —— 加入新公钥 (同时保留原有公钥以兼容旧主机)
    SOPS_YAML="$SCRIPT_DIR/.sops.yaml"
    if ! grep -qF "$PUB_KEY" "$SOPS_YAML" 2>/dev/null; then
      sed -i "/^[[:space:]]*- age:/a\      - ${PUB_KEY}" "$SOPS_YAML" || true
      git -C "$SCRIPT_DIR" add .sops.yaml 2>/dev/null || true
      info ".sops.yaml 已更新 (添加新公钥)"
    fi
  else
    read -r -p "  粘贴 AGE-SECRET-KEY-1 行: " age_key
    if printf '%s\n' "$age_key" | grep -qE '^AGE-SECRET-KEY-1'; then
      printf '%s\n' "$age_key" > "$AGE_KEY_SRC"
      chmod 600 "$AGE_KEY_SRC"
      info "age 密钥已写入 /tmp/sops-age-key"
    else
      die "输入格式不正确, 应以 AGE-SECRET-KEY-1 开头"
    fi
  fi
fi
# ============================================================================
# 阶段 0.55: 从已有 secrets 提取值, 或交互式获取
# ============================================================================
# 优先从已有 secrets/secrets.yaml 解密提取, 失败再回退到参数/交互
SECRETS_FILE="$SCRIPT_DIR/secrets/secrets.yaml"

if [ -f "$AGE_KEY_SRC" ] && [ -s "$SECRETS_FILE" ]; then
  info "检测到已有 secrets/secrets.yaml, 尝试解密提取..."

  # 提取 wbb-password-hash (未通过 -p 传入时)
  if [ -z "$PASS_HASH_ARG" ]; then
    EXISTING_HASH="$(SOPS_AGE_KEY_FILE="$AGE_KEY_SRC" nix --extra-experimental-features "nix-command flakes" \
      shell nixpkgs#sops --command sops -d --extract '["wbb-password-hash"]' "$SECRETS_FILE" 2>/dev/null)" || true
    if [ -n "$EXISTING_HASH" ]; then
      PASS_HASH_ARG="$EXISTING_HASH"
      info "已从现有 secrets 提取密码哈希 (无需重新输入)"
    fi
  fi

  # 提取 github-netrc (未通过 -t 传入时)
  if [ -z "$GITHUB_TOKEN_ARG" ]; then
    EXISTING_NETRC="$(SOPS_AGE_KEY_FILE="$AGE_KEY_SRC" nix --extra-experimental-features "nix-command flakes" \
      shell nixpkgs#sops --command sops -d --extract '["github-netrc"]' "$SECRETS_FILE" 2>/dev/null)" || true
    if [ -n "$EXISTING_NETRC" ]; then
      # 从 netrc 格式 "machine github.com login <user> password <token>" 中提取 token 和用户名
      EXISTING_TOKEN="$(printf '%s' "$EXISTING_NETRC" | grep -oP 'password \K\S+')"
      EXISTING_USER="$(printf '%s' "$EXISTING_NETRC" | grep -oP 'login \K\S+')"
      if [ -n "$EXISTING_TOKEN" ]; then
        GITHUB_TOKEN_ARG="$EXISTING_TOKEN"
        [ -n "$EXISTING_USER" ] && GITHUB_USER_ARG="$EXISTING_USER"
        info "已从现有 secrets 提取 github-netrc (用户: ${GITHUB_USER_ARG:-未知})"
      fi
    fi
  fi
fi

# 提取失败或 secrets 不存在 → 回退到参数或交互
if [ -z "$PASS_HASH_ARG" ]; then
  if [ "$FORCE" -eq 1 ]; then
    die "静默模式 (-f) 请通过 -p 参数提供密码哈希 (mkpasswd -m yescrypt 生成)"
  fi
  info "设置用户密码"
  while true; do
    read -r -s -p "  输入密码: " pass1; echo ""
    read -r -s -p "  确认密码: " pass2; echo ""
    if [ "$pass1" = "$pass2" ] && [ -n "$pass1" ]; then
      PASS_HASH_ARG="$(printf '%s' "$pass1" | \
        nix --extra-experimental-features "nix-command flakes" shell nixpkgs#whois --command mkpasswd -m yescrypt -s)"
      info "密码哈希已生成"
      break
    else
      warn "密码不匹配或为空, 请重试"
    fi
  done
fi

if [ -z "$GITHUB_TOKEN_ARG" ] && [ "$FORCE" -ne 1 ]; then
  warn "未获取到 GitHub token (secrets 中无 github-netrc 且未传 -t)"
  info "将不写入 github-netrc — nix flake 访问公开仓库无需 token"
fi

# ============================================================================
# 阶段 0.6: 自动写入 secrets (从参数)
# ============================================================================
info "[0.6/3] 从参数写入 secrets"
SECRETS_FILE="$SCRIPT_DIR/secrets/secrets.yaml"

# 构建明文内容
SECRETS_CONTENT=""

if [ -n "$GITHUB_TOKEN_ARG" ]; then
  GH_USER="${GITHUB_USER_ARG:-wbb}"
  printf -v SECRETS_CONTENT '%sgithub-netrc: |\n' "$SECRETS_CONTENT"
  printf -v SECRETS_CONTENT '%s  machine github.com login %s password %s\n' "$SECRETS_CONTENT" "$GH_USER" "$GITHUB_TOKEN_ARG"
fi

printf -v SECRETS_CONTENT '%swbb-password-hash: "%s"\n' "$SECRETS_CONTENT" "$PASS_HASH_ARG"

# 创建明文 → 加密
printf '%s' "$SECRETS_CONTENT" > "$SECRETS_FILE"
nix --extra-experimental-features "nix-command flakes" shell nixpkgs#sops --command \
  sops -e -i "$SECRETS_FILE" || die "加密 secrets 失败"
info "secrets 已从参数创建并加密"

# git add
git -C "$SCRIPT_DIR" add secrets/secrets.yaml 2>/dev/null || true

# ============================================================================
# 阶段 1: disko 分区 & 格式化 & 挂载
# ============================================================================
info "[1/3] 分区: disko 格式化 $DISK 并挂载到 /mnt"

# 清理残留挂载 (上次安装失败或中断可能留下)
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
# 用实际设备路径替换 disks.nix 中的占位符
DISKO_CFG="$SCRIPT_DIR/hosts/wbb/disks.nix"
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
# 从 flake.lock 读取锁定的 disko commit, 保持版本一致
DISKO_REV="$([ -f "$SCRIPT_DIR/flake.lock" ] && python3 -c "import json; print(json.load(open("$SCRIPT_DIR/flake.lock"))["nodes"]["disko"]["locked"]["rev"])" 2>/dev/null || echo "")"
nix --extra-experimental-features "nix-command flakes" \
  run "github:nix-community/disko/${DISKO_REV:-master}" -- "${DISKO_FLAGS[@]}" --root-mountpoint /mnt "$DISKO_TMP" \
  || die "disko 分区失败。请检查磁盘是否被占用 (reboot 后重试)。"

mountpoint -q /mnt     || die "挂载失败: /mnt"
mountpoint -q /mnt/nix || die "挂载失败: /mnt/nix"
info "磁盘已分区并挂载到 /mnt (disko)"

rm -f "$DISKO_TMP"

# ---- 持久化 age 密钥到目标系统 ----
# /tmp/sops-age-key 仅在 Live CD 的 tmpfs 中, 重启后销毁。
# 安装时复制一份到 /mnt/root/.config/sops/age/keys.txt,
# nixos-install 阶段 sops-nix 用 /tmp/sops-age-key 解密,
# 重启后 age-keygen 机制被宿主系统 ssops-nix 使用 keys.txt 解密。
if [ -f "$AGE_KEY_SRC" ]; then
  # 写入目标系统 (重启后使用)
  mkdir -p "$AGE_KEY_DST"
  cp "$AGE_KEY_SRC" "$AGE_KEY_DST/keys.txt"
  chmod 700 "$AGE_KEY_DST"
  chmod 600 "$AGE_KEY_DST/keys.txt"
  info "age 密钥已持久化到 /mnt/root/.config/sops/age/keys.txt"

fi

# 阶段 1.5: hardware-configuration.nix
# ============================================================================
info "[1.5/3] 检测硬件: 生成 hardware-configuration.nix"

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
    || echo '  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];')
  HAS_INTEL=$(grep -q 'intel.*updateMicrocode.*true' "$HW_NIX" 2>/dev/null && echo true || echo false)
  HAS_AMD=$(grep -q 'amd.*updateMicrocode.*true' "$HW_NIX" 2>/dev/null && echo true || echo false)
else
  warn "nixos-generate-config 失败, 使用默认硬件检测"
  INITRD_MODS='"ahci" "nvme" "sd_mod" "usb_storage" "usbhid" "uas"
    "xhci_pci" "ehci_pci" "iwlwifi" "iwlmvm" "iwldvm"'
  KERNEL_MODS='  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];'
  HAS_INTEL=true; HAS_AMD=true
fi

# ---- 从 disks.nix 提取文件系统, 写入 supportedFilesystems ----
# 解析 disks.nix 中的 format / type 字段, 提取全部文件系统
DISKO_FS="$(awk '/format =|type =.*"(btrfs|ext4|xfs|f2fs|vfat|ntfs|zfs|tmpfs|exfat)"/   { gsub(/[";]/,"",$3); printf "\"%s\" ", $3 }' "$DISKO_CFG" | sort -u | tr '
' ' ')"

info "检测到文件系统: ${DISKO_FS}"

cat > hosts/wbb/hardware-configuration.nix <<HWEOF
# 硬件配置 —— 由 install.sh 自动生成
{ config, lib, pkgs, modulesPath, ... }:
{
  # 文件系统支持 —— 从 hosts/wbb/disks.nix 自动推导
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

info "hardware-configuration.nix 已生成到 hosts/wbb/"

# ---- 阶段 1.6: git commit (nixos-install --flake 仅读取 git 追踪文件) ----
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
  git -C "$SCRIPT_DIR" add -f hosts/wbb/hardware-configuration.nix 2>/dev/null || true
  git -C "$SCRIPT_DIR" add -f secrets/secrets.yaml .sops.yaml 2>/dev/null || true
  git -C "$SCRIPT_DIR" add -f flake.nix flake.lock hosts/ modules/ secrets/ .sops.yaml 2>/dev/null || true

  # 关键验证: hardware-configuration.nix 必须在 index 中, 否则 nixos-install 必然失败
  if ! git -C "$SCRIPT_DIR" ls-files --error-unmatch hosts/wbb/hardware-configuration.nix >/dev/null 2>&1; then
    die "hardware-configuration.nix 未能添加到 git, 无法继续安装"
  fi

  if git -C "$SCRIPT_DIR" \
    -c user.email="install@nixos.local" \
    -c user.name="NixOS Installer" \
    commit -m "install: hardware-configuration + secrets for $(hostname)"; then
    info "所有文件已提交到 git (含 hardware-configuration.nix + secrets)"
  else
    die "git commit 失败, 无法继续。请检查: git -C $SCRIPT_DIR status"
  fi
else
  die "$SCRIPT_DIR/.git 不存在, 无法 commit。请从 git clone 重新获取本仓库。"
fi

# ============================================================================
# 阶段 2: 启用 swap
# ============================================================================
info "[2/3] 启用 swap"
SWAPFILE="/mnt/swap/swapfile"
if [ -f "$SWAPFILE" ]; then
  swapon "$SWAPFILE" && info "磁盘 swapfile 已启用 (16G)" || warn "swapfile 启用失败, 继续安装"
else
  warn "swapfile 不存在 ($SWAPFILE), disko 可能未创建, 继续安装"
fi
info "总 swap: $(free -m | awk '/Swap:/{print $2}')M"

# ============================================================================
# 阶段 3: nixos-install
# ============================================================================
info "[3/3] nixos-install: 安装 NixOS (请耐心等待)"
# 设置 GOPROXY 使用国内镜像, 避免 proxy.golang.org 超时导致 sops-install-secrets 编译失败
export GOPROXY="https://goproxy.cn,direct"
nixos-install --flake .#wbb --no-channel-copy --no-root-password

swapoff "$SWAPFILE" 2>/dev/null || true
swapoff /dev/zram0 2>/dev/null || true

echo ""; info "安装完成!"; echo ""
echo "下一步:"
echo "  reboot"
echo ""
echo "首次启动后以用户 wbb 登录。"
