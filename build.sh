#!/usr/bin/env bash
# NixOS 统一入口: Live CD → 全新安装 (install.sh); 已装系统 → 日常 switch
# 用法: ./build.sh [-d /dev/xxx] [nixos-rebuild 额外参数...]
# - 检测到 Live CD 环境自动转入 install.sh (需 -d 指定磁盘), 装完重启后
#   同一命令自动转为日常重建 —— 分发接收者只需记一个入口。
# - 已装系统: 每次 switch 前自动硬件适配 (模块/hostPlatform/swapfile 大小/
#   resume_offset, 写入工作区, 构建后还原), 换硬件/加内存后直接 build 即适配。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 公共函数 (host_name 等), 与 install.sh / adapt-hardware.sh 共用
source "$SCRIPT_DIR/scripts/common.sh"

help() {
  cat >&2 <<EOF
  NixOS 统一入口 —— 环境感知: Live CD 安装 / 已装系统日常重建

用法 (环境感知, 按运行环境二选一):
  # Live CD 全新安装 (需 root, 参数转 install.sh)
  ${0##*/} -d /dev/xxx
  # 已装系统日常重建 (额外参数原样透传 nixos-rebuild)
  ${0##*/} [nixos-rebuild 额外参数...]

环境感知:
  Live CD (根为 tmpfs)    → 自动转入 install.sh 全新安装
  已装系统 (磁盘根)        → 硬件适配 + nixos-rebuild switch (日常更新)

选项:
  -d, --disk <设备>       目标磁盘设备 (仅 Live 安装模式, 必需)
  -h, --help               显示本帮助

说明: 全盘确认必须人工参与 ([Y/n] 交互, 无静默跳过开关);
无人值守安装需先人工清盘, 日常重建参数 (如 --build-host ...) 经透传生效。
EOF
  exit "${1:-0}"
}

# -h/--help 在任何环境先拦截 (Live 下不再落入 install.sh 的帮助)
for _arg in "$@"; do
  case "$_arg" in
    -h | --help) help 0 ;;
  esac
done

# ---- 环境感知分流: Live CD → 安装流程 ----
# 判据 (两者任一即 Live): 根为 tmpfs (Live 内存盘) 或存在 /nix/.ro-store
# (ISO squashfs 只读 store 层)。已装系统根为磁盘文件系统且无 overlay store,
# 两者皆假, 稳走下方日常重建。
if [ "$(findmnt -no FSTYPE / 2>/dev/null || true)" = "tmpfs" ] || [ -d /nix/.ro-store ]; then
  info "检测到 Live CD 环境, 转入全新安装流程 (install.sh)"
  exec "$SCRIPT_DIR/scripts/install.sh" "$@"
fi

# 预热 sudo 缓存: adapt-hardware.sh 的 resume_offset 探测需 root 挂载 @swap,
# 提前在此输入密码 (build 本就要密码), 探测走 sudo -n 免密; 无 tty 时
# (CI/自动化) sudo -v 失败也不阻断, 探测跳过并保留占位, hibernate-now 运行时告警兜底。
sudo -v || true

# ---- swapfile 漂移检测与方向分级处理 (必须在本轮 adapt 之前执行) ----
# swapfile 由 disko 安装时一次创建, adapt 只改配置不重建 —— 换内存后"自动
# 跟随"是假象。目标值直接按内存等大现算 (同 adapt 公式, 不读 disks.nix:
# 那是 adapt 改写前的旧值)。放在 adapt 前: 重建后 adapt 探测新 swapfile 的
# resume_offset, 本次构建即带正确偏移。
# 方向分级 (危险×安全配对):
#   目标 > 实际 (内存变大): swap < RAM → 休眠失效 (功能危险); 但 swapoff 小
#     内容回灌大内存无 OOM → 自动重建 (安全修复)
#   目标 < 实际 (内存变小): swap ≥ RAM 依旧满足 → 无功能影响, 仅提示 (自动
#     收缩需 swapoff 大内容回灌小内存 = OOM 风险, 永不自动)
MEM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}' 2>/dev/null || echo 4096)
TARGET_SWAP_G=$(( (MEM_MB + 1023) / 1024 ))
SWAP_FILE=/swap/swapfile
if [ -f "$SWAP_FILE" ]; then
  SWAP_ACT_G=$(stat -c %s "$SWAP_FILE" 2>/dev/null | awk '{printf "%d", $1/1073741824}')
  if [ "${SWAP_ACT_G:-0}" -lt "$TARGET_SWAP_G" ]; then
    warn "swapfile ${SWAP_ACT_G}G < 内存等大 ${TARGET_SWAP_G}G: 休眠将失效, 尝试自动重建"
    SWAP_USED_M=$(swapon --show=USED --bytes --noheadings 2>/dev/null \
      | awk '{s+=$1} END{printf "%d", s/1024/1024}')
    # 可用内存直接读 /proc/meminfo MemAvailable: free 的表头随 locale 本地化
    # (中文为"内存:"), awk '/Mem:/' 匹配失败致 FREE_M 空、判据恒假误跳重建
    FREE_M=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    if [ "${SWAP_USED_M:-0}" -lt "${FREE_M:-0}" ]; then
      if sudo swapoff "$SWAP_FILE" 2>/dev/null \
         && sudo rm -f "$SWAP_FILE" \
         && (sudo fallocate -l "${TARGET_SWAP_G}G" "$SWAP_FILE" \
             || sudo truncate -s "${TARGET_SWAP_G}G" "$SWAP_FILE") \
         && sudo chmod 600 "$SWAP_FILE" \
         && sudo mkswap "$SWAP_FILE" >/dev/null 2>&1 \
         && sudo swapon "$SWAP_FILE"; then
        info "swapfile 已重建: ${SWAP_ACT_G}G → ${TARGET_SWAP_G}G (resume_offset 由本轮适配探测修正)"
      else
        warn "swapfile 自动重建失败, 请人工处理 (swapoff → 重建 → mkswap → swapon)"
      fi
    else
      warn "swap 使用量高 (${SWAP_USED_M}M ≥ 可用内存 ${FREE_M}M), 跳过自动重建, 请人工处理"
    fi
  elif [ "${SWAP_ACT_G:-0}" -gt "$TARGET_SWAP_G" ]; then
    info "swapfile ${SWAP_ACT_G}G > 内存等大 ${TARGET_SWAP_G}G: 无影响 (休眠约束满足); 需回收磁盘可人工收缩"
  fi
fi

bash scripts/adapt-hardware.sh

HOST_NAME="$(host_name)"

# 构建用适配后的工作区文件; 成功后还原 (系统已固化, 仓库保持干净)
sudo nixos-rebuild switch --flake ".#${HOST_NAME}" "$@"

restore_adapt
info "硬件适配文件已还原 (系统已固化, 仓库保持干净)"
