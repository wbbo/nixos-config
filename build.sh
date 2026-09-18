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
#   目标 < 实际 (内存变小): swap ≥ RAM 依旧满足 → 无功能影响; 磁盘 swap
#     用量为 0 时 swapoff 无内容回灌、零 OOM 风险 → 自动收缩; 有内容时
#     swapoff 回灌小内存 = OOM 风险 → 仅提示人工处理
MEM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}' 2>/dev/null || echo 4096)
TARGET_SWAP_G=$(( (MEM_MB + 1023) / 1024 ))
SWAP_FILE=/swap/swapfile
if [ -f "$SWAP_FILE" ]; then
  SWAP_ACT_G=$(stat -c %s "$SWAP_FILE" 2>/dev/null | awk '{printf "%d", $1/1073741824}')
  # 激活态校验: 大小达标 ≠ 可用 (失败残骸/激活失败会留下合法大小的死文件)
  SWAP_ACTIVE=0
  swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$SWAP_FILE" && SWAP_ACTIVE=1
  if [ "${SWAP_ACT_G:-0}" -lt "$TARGET_SWAP_G" ]; then
    warn "swapfile ${SWAP_ACT_G}G < 内存等大 ${TARGET_SWAP_G}G: 休眠将失效, 尝试自动重建"
    SWAP_USED_M=$(swapon --show=USED --bytes --noheadings 2>/dev/null \
      | awk '{s+=$1} END{printf "%d", s/1024/1024}')
    # 可用内存直接读 /proc/meminfo MemAvailable: free 的表头随 locale 本地化
    # (中文为"内存:"), awk '/Mem:/' 匹配失败致 FREE_M 空、判据恒假误跳重建
    FREE_M=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    # 重建走 btrfs filesystem mkswapfile (与 disko 安装路径同源): 内部设
    # NOCOW + fallocate + mkswap。不能手写 fallocate/truncate+mkswap —— 无
    # NOCOW 时 swapon 报 EINVAL "swapfile must not be copy-on-write"
    # (truncate 稀疏文件同样不可 swapon); mkswap 不校验 COW, 失败晚暴露。
    if [ "${SWAP_USED_M:-0}" -lt "${FREE_M:-0}" ]; then
      if sudo swapoff "$SWAP_FILE" 2>/dev/null \
         && sudo rm -f "$SWAP_FILE" \
         && sudo btrfs filesystem mkswapfile --size "${TARGET_SWAP_G}G" "$SWAP_FILE" \
         && sudo chmod 600 "$SWAP_FILE" \
         && sudo swapon "$SWAP_FILE"; then
        info "swapfile 已重建: ${SWAP_ACT_G}G → ${TARGET_SWAP_G}G (resume_offset 由本轮适配探测修正)"
      else
        # 清残骸: 残留完整大小文件会落入下方"达标未激活"分支之外被永久无视
        sudo rm -f "$SWAP_FILE" 2>/dev/null || true
        warn "swapfile 自动重建失败, 请人工处理 (swapoff → btrfs filesystem mkswapfile → swapon)"
      fi
    else
      warn "swap 使用量高 (${SWAP_USED_M}M ≥ 可用内存 ${FREE_M}M), 跳过自动重建, 请人工处理"
    fi
  elif [ "$SWAP_ACTIVE" = 0 ]; then
    # 大小达标但未激活: 补激活一次 (可能是漏挂载); 失败即残骸/损坏, 人工重建
    if sudo swapon "$SWAP_FILE" 2>/dev/null; then
      info "swapfile ${SWAP_ACT_G}G 达标但此前未激活, 已重新挂载"
    else
      warn "swapfile ${SWAP_ACT_G}G 无法激活 (失败残骸/损坏), 请人工处理: rm $SWAP_FILE 后 btrfs filesystem mkswapfile --size ${TARGET_SWAP_G}G $SWAP_FILE"
    fi
  elif [ "${SWAP_ACT_G:-0}" -gt "$TARGET_SWAP_G" ]; then
    # 收缩方向: 安全前提 = 磁盘 swap 用量为 0 (swapoff 无内容回灌, 零 OOM
    # 风险)。用量按本文件单独统计 (SWAP_USED_M 是 zram+磁盘总和, 不能用):
    # 内容压在 zram 里时磁盘 swapoff 仍无回灌, 收缩照常安全。
    SWAP_FILE_USED_KB=$(swapon --show=NAME,USED --bytes --noheadings 2>/dev/null \
      | awk -v f="$SWAP_FILE" '$1==f{print $2}')
    if [ "${SWAP_FILE_USED_KB:-0}" -eq 0 ] && [ "$SWAP_ACTIVE" = 1 ]; then
      if sudo swapoff "$SWAP_FILE" 2>/dev/null \
         && sudo rm -f "$SWAP_FILE" \
         && sudo btrfs filesystem mkswapfile --size "${TARGET_SWAP_G}G" "$SWAP_FILE" \
         && sudo chmod 600 "$SWAP_FILE" \
         && sudo swapon "$SWAP_FILE"; then
        info "swapfile 已收缩: ${SWAP_ACT_G}G → ${TARGET_SWAP_G}G (用量 0, resume_offset 由本轮适配探测修正)"
      else
        # 清残骸: rm 失败的半重建文件会在下轮落入无关分支被永久无视
        sudo swapon "$SWAP_FILE" 2>/dev/null || true
        warn "swapfile 自动收缩失败 (已尝试重新挂载原文件), 请人工处理"
      fi
    else
      info "swapfile ${SWAP_ACT_G}G > 内存等大 ${TARGET_SWAP_G}G: 无影响 (休眠约束满足)"
      if [ "$SWAP_ACTIVE" = 1 ]; then
        info "  需回收磁盘可人工收缩 (swap 使用中 ${SWAP_FILE_USED_KB:-?}KB, 自动收缩有回灌 OOM 风险):"
      else
        info "  swapfile 未激活, 人工收缩前先确认其状态:"
      fi
      info "  sudo swapoff $SWAP_FILE && sudo rm $SWAP_FILE && sudo btrfs filesystem mkswapfile --size ${TARGET_SWAP_G}G $SWAP_FILE && sudo chmod 600 $SWAP_FILE && sudo swapon $SWAP_FILE"
    fi
  fi
fi

# 构建期适配: 把本机硬件值 (hostPlatform / swapfile 大小 / resume_offset)
# 写进 hardware-configuration.nix / disks.nix / boot.nix。
# 用 trap 兜底还原 —— switch 失败 / Ctrl-C / 任何 set -e 退出路径都会还原。
# 没有它时, 构建中途失败会把本机专属值留在工作区, 一旦顺手 commit 就进了
# 分发模板 (2026-09-14 实际发生过: HM 激活失败, 三个文件残留在适配状态,
# 直到下一次构建成功才被顺手还原)。
restore_adapt_and_report() {
  restore_adapt
  info "硬件适配文件已还原 (系统已固化, 仓库保持干净)"
}
trap restore_adapt_and_report EXIT

# ---- HM 管理路径实体文件预检 ----
# Home Manager 只对「跨代际内容有变化」的管理路径做链接检查, 因此在其管理
# 路径下手动落下的实体文件是**定时炸弹**: 平时静默通过, 直到该文件内容因
# 依赖升级等发生变化, HM 拒绝覆盖 → 激活失败 (半激活: NixOS 侧切换成功,
# 用户态配置全部未生效, 退出码 4)。
# 实例: 2026-09-09 一次排查中的 cp 在 ~/.config/systemd/user/ 埋下实体单元
# 文件, 直到 09-14 nixpkgs 更新改变单元内容才引爆 —— 详见 CLAUDE.md
# 「代码审查与修复记录」。同类问题在本仓库已发生 4 次 (fonts/fish/fcitx5
# 各自用 force = true 兜住, 而 systemd.user.services 没有 force 选项)。
# 这里用当前代际的 home-files 树做期望清单提前曝光; **只告警不中止** ——
# 文件内容未变时本次构建本可成功, 不该被预检拦下。
# 局限: 只覆盖当前代际已在管的路径; 新代际新增路径若撞上实体文件仍由 HM
# 自行报错 (那时至少 trap 已保证仓库不被污染)。
target_home() {
  local u="${SUDO_USER:-}"
  if [ -n "$u" ] && [ "$u" != "root" ]; then
    getent passwd "$u" 2>/dev/null | cut -d: -f6
  else
    printf '%s\n' "$HOME"
  fi
}

preflight_hm_clobber() {
  local h genc hf rel n=0
  h="$(target_home)"
  if [ -z "$h" ] || [ ! -d "$h" ]; then
    return 0
  fi
  # 注意: genc 是**未解析**的 gcroots 路径 —— home-files 本身是指向
  # /nix/store/<hash>-home-manager-files 的符号链接, 对它 readlink -f 后再
  # dirname 只会得到 /nix/store (activate 在代际目录里, 不在 store 树里)。
  genc="$h/.local/state/home-manager/gcroots/current-home"
  hf="$(readlink -f "$genc/home-files" 2>/dev/null)" || true
  if [ -z "$hf" ] || [ ! -d "$hf" ]; then
    return 0
  fi

  # force 清单 —— 取自 HM 自己的产物, 不维护第二份列表 (force 增删自动跟随):
  # 激活脚本调用的 check-link-targets.sh 里有 `forcedPaths=("$HOME"/a "$HOME"/b)`,
  # 由 HM 依据各文件的 force = true 生成。这些路径 HM **跳过冲突检查**,
  # linkGeneration 又用 `ln -Tsf` 强制替换, 实体文件永远不会 clobbered 失败 ——
  # 应用运行时会改写它们 (如 firefox 的 search.json.mozlz4 / fcitx5 的 profile),
  # 属正常现象。纳入告警只会制造每次 rebuild 都出现的噪声, 让人对真信号脱敏。
  local -a forced=()
  local check_script fp
  check_script="$(grep -oE '/nix/store/[a-z0-9]+-check-link-targets\.sh' "$genc/activate" 2>/dev/null | head -1)" || true
  if [ -n "$check_script" ] && [ -r "$check_script" ]; then
    # [^" )] 排除右括号 —— 数组字面量的末尾是 `"...mozlz4)` (Bash 数组以 ) 收尾),
    # 不排除会把最后一条的 ) 一起吞进来, 那条就永远匹配不上 (实测踩到)
    mapfile -t forced < <(grep -oE '"\$HOME"/[^" )]+' "$check_script" | sed 's|^"\$HOME"/||')
  fi

  while IFS= read -r -d '' f; do
    rel="${f#"$hf/"}"
    if [ -L "$h/$rel" ]; then continue; fi  # 正常: HM 的符号链接
    if [ ! -e "$h/$rel" ]; then continue; fi # 不存在: 无冲突
    for fp in "${forced[@]}"; do
      # 与 HM 自身一致用前缀匹配 (check-link-targets.sh: $targetPath == $forcedPath*)
      if [ "${rel#"$fp"}" != "$rel" ]; then
        continue 2
      fi
    done
    if [ "$n" -eq 0 ]; then
      warn "HM 管理路径下出现实体文件 (定时炸弹, 见 CLAUDE.md 代码审查记录):"
    fi
    n=$((n + 1))
    warn "  $h/$rel"
  done < <(find "$hf" ! -type d -print0 2>/dev/null || true)
  if [ "$n" -gt 0 ]; then
    warn "共 $n 个。**内容跨代际变化时** HM 才拒绝覆盖导致激活失败, 平时静默 ——"
    warn "本次构建仍可能成功。建议顺手清掉 (确认内容后):"
    warn "  mv <该文件> <该文件>.stale-\$(date +%Y%m%d)   # HM 随即重建符号链接"
    if [ "${#forced[@]}" -gt 0 ]; then
      warn "  (${#forced[@]} 个 force = true 管理的路径已跳过 —— 那些位置 HM 每次激活强制覆盖, 无害)"
    fi
  fi
}

preflight_hm_clobber

bash scripts/adapt-hardware.sh

HOST_NAME="$(host_name)"

# 构建用适配后的工作区文件; 退出时由上方 trap 还原 (系统已固化)
sudo nixos-rebuild switch --flake ".#${HOST_NAME}" "$@"
