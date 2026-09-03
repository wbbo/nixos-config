#!/usr/bin/env bash
# 硬件适配脚本: 检测当前硬件 → 更新仓库配置
#   - hosts/<hostDir>/hardware-configuration.nix (模块/hostPlatform)
#   - hosts/<hostDir>/disks.nix (swapfile 大小, 休眠要求 swap ≥ RAM)
# 每次 nixos-rebuild 前运行 (rebuild.sh 自动调用); install.sh 安装时同样调用。
# 适配写入工作区, nix path fetcher (--flake /path) 直接读取 (构建后由调用方
# install.sh/rebuild.sh 的 restore_adapt 还原)。
# 注意: nixos-generate-config 的硬件检测基于当前运行系统, --root 仅决定输出路径,
# 用临时目录避免污染 /etc/nixos。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# 公共函数 (info/warn/die/host_name/host_dir), 与 install.sh / rebuild.sh 共用
source "$SCRIPT_DIR/scripts/common.sh"

# 主机名/主机目录 (解析逻辑见 common.sh)
HOST_NAME="$(host_name)"
HOST_DIR="$(host_dir)"

# git 安全检查 (Live CD / 属主不一致场景; 与 install.sh 原逻辑一致)
git config --global --add safe.directory "$SCRIPT_DIR" 2>/dev/null || true
# index 属主修复仅普通用户需要: root 对任何属主都有全权, 若 root 把 index
# chown 成 root, 普通用户下次进来 chown 不动, 曾经的 rm 兜底会删掉 index ——
# index 一丢 git 全库变 untracked, flake 求值树为空, 构建必炸。故 root 跳过,
# 普通用户先 own 再借 sudo (rebuild.sh 已 sudo -v 预热), rm 只留最后兜底。
if [ "$(id -u)" != 0 ] && [ -f .git/index ] && [ "$(stat -c %u .git/index 2>/dev/null)" != "$(id -u)" ]; then
  chown "$(id -u):$(id -g)" .git/index 2>/dev/null \
    || sudo chown "$(id -u):$(id -g)" .git/index 2>/dev/null \
    || rm -f .git/index
fi

# ---- 1. hostPlatform: nix 内建 currentSystem (标准平台名, 免 uname 映射) ----
# 不能省略该行: nixpkgs 的 hostPlatform 无默认值, 未设置会直接 throw
HOST_PLATFORM="$(nix-instantiate --eval --raw --expr 'builtins.currentSystem' 2>/dev/null)"

# ---- 2. swapfile 大小: 与内存等大 (上取整) —— 休眠要求 swap ≥ 内存 ----
MEM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}' 2>/dev/null || echo 4096)
SWAP_SIZE_G=$(( (MEM_MB + 1023) / 1024 ))   # 上取整, 保证 swap ≥ RAM

# ---- 3. 硬件模块提取 (nixos-generate-config, 输出到临时目录) ----
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
nixos-generate-config --root "$TMP_ROOT" 2>/dev/null || true
HW_NIX="$TMP_ROOT/etc/nixos/hardware-configuration.nix"
if [ -f "$HW_NIX" ]; then
  # 纯文本 index() 定位, 兼容单行/多行/尾行闭合格式
  extract_mods() {
    awk -v attr="$1" '
      {
        n = index($0, attr)
        if (n > 0) {
          rest = substr($0, n + length(attr))
          sub(/^[[:space:]]*\[[[:space:]]*/, "", rest)   # 剥 `[` 及空白
          if (rest ~ /];/) { sub(/[[:space:]]*];.*/, "", rest); print rest; exit }
          print rest
          while (getline > 0) {
            if ($0 ~ /^[[:space:]]*];/) exit    # 纯闭合行: 直接退出
            sub(/[[:space:]]*];.*/, "")          # 模块与 ]; 同行: 剥掉闭合符
            print
          }
          exit
        }
      }
    ' "$HW_NIX"
  }
  INITRD_MODS=$(extract_mods 'boot.initrd.availableKernelModules = ')
  # 注意: extract_mods 输出括号内值, heredoc 中 initrd.kernelModules/kernelModules
  # 需要完整语句, 此处包一层 (裸值直接拼 heredoc 会生成非法 Nix)
  INITRD_KMODS_VALS=$(extract_mods 'boot.initrd.kernelModules = ')
  if [ -n "$INITRD_KMODS_VALS" ]; then
    INITRD_KMODS="  boot.initrd.kernelModules = [ ${INITRD_KMODS_VALS} ];"
  else
    INITRD_KMODS='  boot.initrd.kernelModules = [ ];'
  fi
  KERNEL_MODS_VALS=$(extract_mods 'boot.kernelModules = ')
  if [ -n "$KERNEL_MODS_VALS" ]; then
    KERNEL_MODS="  boot.kernelModules = [ ${KERNEL_MODS_VALS} ];"
  else
    KERNEL_MODS='  boot.kernelModules = [ ];'
  fi
  if [ -z "$INITRD_MODS" ]; then
    warn "无法从 hardware-configuration.nix 提取内核模块, 使用默认值"
    INITRD_MODS='"ahci" "nvme" "sd_mod" "usb_storage" "usbhid" "uas"
      "xhci_pci" "ehci_pci" "iwlwifi" "iwlmvm" "iwldvm"'
  fi
else
  warn "nixos-generate-config 失败, 使用默认硬件检测"
  INITRD_MODS='"ahci" "nvme" "sd_mod" "usb_storage" "usbhid" "uas"
    "xhci_pci" "ehci_pci" "iwlwifi" "iwlmvm" "iwldvm"'
  INITRD_KMODS='  boot.initrd.kernelModules = [ ];'
  KERNEL_MODS='  boot.kernelModules = [ ];'
fi

# ---- 4. 文件系统列表 (从 disks.nix 提取, 写入 supportedFilesystems) ----
# 仅收已知文件系统 (防 `type = {` 内联风格误取), 允许尾分号
DISKO_CFG="hosts/${HOST_DIR}/disks.nix"
DISKO_FS="$(awk '/format =[[:space:]]*"(btrfs|ext4|xfs|f2fs|vfat|ntfs|zfs|tmpfs|exfat)"|type =[[:space:]]*"(btrfs|ext4|xfs|f2fs|vfat|ntfs|zfs|tmpfs|exfat)"/ { for (i=1; i<=NF; i++) if ($i ~ /^"(btrfs|ext4|xfs|f2fs|vfat|ntfs|zfs|tmpfs|exfat)"[;[:space:]]*$/) { gsub(/[;]/, "", $i); printf "%s\n", $i } }' "$DISKO_CFG" | sort -u | tr '\n' ' ')"

# ---- 5. 写 hardware-configuration.nix ----
mkdir -p "hosts/${HOST_DIR}"
replace_preserving_owner "hosts/${HOST_DIR}/hardware-configuration.nix" <<HWEOF
# 硬件配置 —— 由 scripts/adapt-hardware.sh 自动生成 (每次 rebuild 前更新)
{ lib, modulesPath, ... }:
{
  # 文件系统支持 —— 从 hosts/${HOST_DIR}/disks.nix 自动推导
  boot.initrd.supportedFilesystems = [ ${DISKO_FS} ];
  boot.initrd.availableKernelModules = [
${INITRD_MODS}
  ];
${INITRD_KMODS}
${KERNEL_MODS}
  nixpkgs.hostPlatform = lib.mkDefault "${HOST_PLATFORM}";
}
HWEOF

# ---- 6. 重写 disks.nix swapfile 大小 (与 hardware-configuration.nix 同理: 每次适配覆盖) ----
# sed_replace: 临时文件中转写回, 防"读目标/截断目标"竞态 (见 common.sh 注释)
if grep -q 'swap\.swapfile\.size' "$DISKO_CFG"; then
  sed_replace "s|swap\.swapfile\.size = \"[^\"]*\"|swap.swapfile.size = \"${SWAP_SIZE_G}G\"|" "$DISKO_CFG"
else
  warn "disks.nix 未找到 swap.swapfile.size, 保持现有值"
fi

# ---- 8. resume_offset: btrfs swapfile 物理偏移 (内核唤醒侧只认 cmdline) ----
# btrfs balance 移动 swapfile / 换盘重装都会让偏移失效, 常规 rebuild 时注入
# boot.nix (构建期临时状态, 构建后 restore 还原占位 0) 保证与当前布局一致。
# 安装场景 (ADAPT_SKIP_RESUME=1, install.sh 在 disko 之前调用本脚本) 跳过:
# 那时新盘未格式化 (by-label/nixos 不存在, root 也探不到), 或重装同机时旧盘
# label 仍在 —— 探到的是即将被 zap 的 stale 值, 注入反而有害; 首装真实值由
# install.sh 在 disko 之后对 /mnt/swap/swapfile 补探注入。
# 探测需 root (挂载 @swap + btrfs map-swapfile): root 直跑; 非 root 时 sudo -n
# (rebuild.sh 已 sudo -v 预热缓存); 都不可用则跳过, 保留仓库占位 ——
# hibernate-now 休眠前检测 cmdline 与实测不符会告警提示 rebuild, 不静默丢会话。
probe_resume_offset() {
  local dev=""
  local tmp=""
  local offset=""
  # by-label 路径在挂载探测时最稳定 (格式化 -L nixos 设定, 与 disks.nix 一致)
  if [ -e "/dev/disk/by-label/nixos" ]; then
    dev="/dev/disk/by-label/nixos"
  elif [ -e "/dev/disk/by-label/root" ]; then
    dev="/dev/disk/by-label/root"
  else
    # 无匹配 label (分发接收者/VM 未设卷标): 探测无意义, 返回空
    # 注意: 不能 return 1 —— 调用处命令替换 + set -e 会炸掉整个脚本
    return 0
  fi
  tmp="$(mktemp -d)"
  # RETURN trap: 函数级还原 (umount 失败时 rmdir 静默, 目录残留无害)
  trap 'umount "$tmp" 2>/dev/null || true; rmdir "$tmp" 2>/dev/null || true' RETURN
  mount -t btrfs -o subvol=@swap,noatime "$dev" "$tmp" 2>/dev/null || return 0
  offset="$(btrfs inspect-internal map-swapfile -r "$tmp/swapfile" 2>/dev/null || true)"
  [ -n "$offset" ] && echo "$offset"
}
RESUME_OFFSET=""
if [ "${ADAPT_SKIP_RESUME:-0}" = 1 ]; then
  info "跳过 resume_offset 探测 (安装场景 disko 前无有效值, disko 后由 install.sh 补探)"
elif [ "$(id -u)" = 0 ]; then
  RESUME_OFFSET="$(probe_resume_offset || true)"
  [ -n "$RESUME_OFFSET" ] || warn "root 下探测失败 (无 by-label/nixos 设备, 或 @swap 挂载/读取失败), 保留 boot.nix 现有值"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  # sudo bash 不继承源脚本函数, declare -f 序列化传入; || true: 探测失败
  # 只算"未探测", 绝不能携非零退出撞上 set -e 炸掉适配
  RESUME_OFFSET="$(sudo bash -c "$(declare -f probe_resume_offset); probe_resume_offset" || true)"
  [ -n "$RESUME_OFFSET" ] || warn "sudo 下探测失败 (@swap 挂载/读取失败), 保留 boot.nix 现有值"
else
  warn "非 root 且 sudo 无缓存, 跳过 resume_offset 探测, 保留 boot.nix 现有值 —— 休眠唤醒依赖 hibernate-now 运行时告警"
fi
if [ -n "$RESUME_OFFSET" ]; then
  inject_resume_offset "$RESUME_OFFSET"
  info "resume_offset=${RESUME_OFFSET} 已注入 boot.nix (构建期临时状态, 构建后还原)"
fi

# ---- 9. (已移除 git add) nix path fetcher 读工作区内容, 与 index 无关; 已跟踪
# 文件的修改两种 fetcher (path/git+file) 均可见, 无需暂存 ----

info "硬件适配完成: hostPlatform=${HOST_PLATFORM:-?}, swapfile=${SWAP_SIZE_G}G, resume_offset=${RESUME_OFFSET:-未探测} (构建期临时状态, 构建后还原)"
