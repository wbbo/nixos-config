#!/usr/bin/env bash
# 企业微信 (Bottles/Wine) 适配 —— 幂等的自检 + 补齐。
#
# 背景: 企业微信的适配全部落在 wine prefix 内部 (runner / 注册表 / 字体), 都是
# Bottles GUI 手工配置的产物, 非声明式 —— 重建 bottle、重装系统、换机后全部丢失,
# 表现为黑屏 / 崩溃循环 / 字体难看。本脚本把 doc/wework.md 记录的成功配置固化成
# 幂等自检, 由 systemd 服务调用 (激活时 + 定期重试, 见 default.nix)。
#
# 覆盖三项 (逐项自检, 已就绪则跳过):
#   1. runner 必须为 caffe 系 —— soda 系 (Proton 游戏补丁) 与企业微信 CEF 冲突,
#      导致 TxBugReport 崩溃循环 (doc/wework.md §2.2)
#   2. XWeb (内嵌浏览器) 硬件加速策略注册表 —— 不禁用则主窗/新窗口持续黑屏 (§2.1)
#   3. 字体替换注册表 —— 把 Windows 界面字体名映射到原版 Maple Mono NF CN
#      (wine 自动扫描宿主字体, 无需拷贝字体文件)
#
# 明确不做: ARGB 子窗 unmap (那是 wework-fix 常驻守护的职责)、fcitx5 XIM
# (由 fcitx5.nix 负责)。
#
# 幂等性: 三项自检都读 prefix 内的实际状态 (bottle.yml / *.reg / Fonts/), 而非
# "跑过没有"。因此手工改回 soda runner 后, 下一轮会自动纠正回来。
#
# 环境: 无 (字体走 wine 的宿主字体扫描, 不需要注入路径)
set -euo pipefail

BOTTLE_NAME="Work"
RUNNER="caffe-10.0"
# runner 包校验和 (Bottles 组件仓库 caffe-10.0.yml 登记的 md5)
RUNNER_MD5="07c2c5c23ff95776e337827cd066b929"
RUNNER_URL="https://github.com/bottlesdevs/wine/releases/download/caffe-10.0/caffe-10.0-x86_64.tar.xz"

BOTTLES_ROOT="$HOME/.var/app/com.usebottles.bottles/data/bottles"
BOTTLE_DIR="$BOTTLES_ROOT/bottles/$BOTTLE_NAME"
PREFIX="$BOTTLE_DIR/drive_c"

# flatpak 调用开销大且每次都刷 GL 噪声 (libGLX_nvidia / DXVK 探测), 与结论无关
NOISE='libGLX_nvidia|Unable to locate|MESA-INTEL|Found device|Skipping:|DXVK|OpenVR|OpenXR|Vulkan|instance|WSI|stdout decoding'
# bottles-cli run (regedit) / edit (换 runner 触发 prefix 更新) 都可能耗时数分钟
CLI_TIMEOUT=300

log() { printf '%s\n' "$*"; }

# 代理探测: 直连不可达的环境 (github 时通时不通) 需要走 mihomo mix-port。
# 与本仓库其他安装类服务 (claude/codex/cc-switch) 同一约定; 无代理环境零影响。
setup_proxy() {
  for _ in 1 2 3; do
    if timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/7890' 2>/dev/null; then
      export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
      return 0
    fi
    sleep 2
  done
}

# 调用 bottles-cli 并过滤噪声; 返回 bottles-cli 自身的退出码
# (set -e 下调用点需自行 || true, 或包在 if 中)
bottles_cli() {
  local out status
  out="$(timeout "$CLI_TIMEOUT" flatpak run --command=bottles-cli com.usebottles.bottles "$@" 2>&1)" && status=0 || status=$?
  printf '%s\n' "$out" | grep -Ev "$NOISE" || true
  return "$status"
}

# 写入一个 UTF-16LE + BOM 的 .reg (wine regedit 只认这种编码) 并导入。
# $1 = prefix 内的目标文件名; stdin = UTF-8 的 .reg 内容
import_reg() {
  local name="$1" tmp
  tmp="$(mktemp -d)"
  iconv -f UTF-8 -t UTF-16LE > "$tmp/body"
  printf '\xff\xfe' > "$tmp/reg"
  cat "$tmp/body" >> "$tmp/reg"
  cp "$tmp/reg" "$PREFIX/$name"
  rm -rf "$tmp"
  bottles_cli run -b "$BOTTLE_NAME" -e 'C:\windows\regedit.exe' /S "C:\\$name" >/dev/null || true
  # regedit 的退出码不反映导入结果 (S 模式下静默), 成功与否由调用方的自检复核。
  # 导入后即删: 就算这次失败, 自检不过下轮会重新导入, 不留垃圾文件。
  rm -f "$PREFIX/$name"
  # wineserver 常驻并缓存注册表 (doc/wework.md 踩坑清单): 停掉它, 保证下次
  # 启动企业微信时读到的是新值。此处企业微信必然未运行 (main 已检查)。
  bottles_cli stop -b "$BOTTLE_NAME" >/dev/null || true
}

# ── 1. runner ─────────────────────────────────────────────────────────────
# runner 包必须先落到 runners/, bottles-cli --runner 才认这个值 (缺包时静默失败)。
ensure_runner() {
  local cur
  cur="$(sed -n 's/^Runner: *//p' "$BOTTLE_DIR/bottle.yml" 2>/dev/null)"
  if [ "$cur" = "$RUNNER" ]; then
    log "runner 已是 $RUNNER, 跳过"
    return 0
  fi
  log "runner 当前为 '$cur', 切换到 $RUNNER"

  local runner_dir="$BOTTLES_ROOT/runners/$RUNNER"
  if [ ! -x "$runner_dir/bin/wine" ]; then
    log "下载 runner $RUNNER"
    setup_proxy
    local tmp
    tmp="$(mktemp -d)"
    if ! curl -L --connect-timeout 10 --max-time 600 --retry 3 --retry-delay 5 \
        -o "$tmp/runner.tar.xz" "$RUNNER_URL"; then
      rm -rf "$tmp"
      log "警告: runner 下载失败, 保留当前 runner"
      return 1
    fi
    if [ "$(md5sum "$tmp/runner.tar.xz" | cut -d' ' -f1)" != "$RUNNER_MD5" ]; then
      rm -rf "$tmp"
      log "警告: runner 校验和不符, 放弃安装"
      return 1
    fi
    # 包内顶层是 caffe-10.0-x86_64/, Bottles 期望 runners/<name>/{bin,lib,share}
    mkdir -p "$runner_dir"
    tar xf "$tmp/runner.tar.xz" -C "$tmp" --strip-components=1
    cp -a "$tmp/bin" "$tmp/lib" "$tmp/share" "$runner_dir/"
    if [ -d "$tmp/include" ]; then
      cp -a "$tmp/include" "$runner_dir/"
    fi
    rm -rf "$tmp"
    log "runner 包已解到 $runner_dir"
  fi

  bottles_cli edit -b "$BOTTLE_NAME" --runner "$RUNNER" >/dev/null \
    || log "警告: bottles-cli edit 非零退出 (超时或失败)"
  # edit 换 runner 会触发 wineprefix 更新 (wineboot), 更新拉起的 explorer 会
  # 执行企业微信的自启动键 (HKCU Run, "-min -autorun") —— 实测正是它把整个
  # wine 会话挂起不返 (edit 等会话退出)。停掉会话让 edit 收尾, 也避免留下
  # 无人认领的企业微信实例。
  bottles_cli stop -b "$BOTTLE_NAME" >/dev/null || true
  log "runner 现为: $(sed -n 's/^Runner: *//p' "$BOTTLE_DIR/bottle.yml")"
}

# ── 2. XWeb 硬件加速策略 ──────────────────────────────────────────────────
# 企业微信的 CEF/XWeb 把 GPU 合成内容画在 32 位 ARGB 子窗, NVIDIA +
# xwayland-satellite 下该子窗读不到内容 → 整窗黑。禁用硬件加速让内容回到
# GDI 层, 是消除黑屏的关键修复 (doc/wework.md §2.1)。Chrome 与 Chromium 两个
# 产品名各写 HKLM/HKCU 四处, 覆盖 32/64 位视图与机器级/用户级策略。
read -r -d '' POLICY_REG <<'EOF' || true
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Chrome]
"HardwareAccelerationModeEnabled"=dword:00000000

[HKEY_CURRENT_USER\SOFTWARE\Policies\Google\Chrome]
"HardwareAccelerationModeEnabled"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Chromium]
"HardwareAccelerationModeEnabled"=dword:00000000

[HKEY_CURRENT_USER\SOFTWARE\Policies\Chromium]
"HardwareAccelerationModeEnabled"=dword:00000000
EOF

ensure_policy() {
  # 自检: HKCU\Chrome (最常命中的键位) 已置 0 即认为就绪
  if grep -A2 'Software..Policies..Google..Chrome\]' "$BOTTLE_DIR/user.reg" 2>/dev/null \
      | grep -q '"HardwareAccelerationModeEnabled"=dword:00000000'; then
    log "XWeb 硬件加速策略已就位, 跳过"
    return 0
  fi
  log "写入 XWeb 硬件加速禁用策略"
  printf '%s\n' "$POLICY_REG" | import_reg policy.reg
}

# ── 3. 字体替换 ───────────────────────────────────────────────────────────
# doc/wework.md §一: 把 Windows 界面字体名映射到 Maple Mono NF CN, 统一观感。
#
# 曾用自建 "Maple Mono NF CN Hybrid" (英文 Regular 字形 + 中文 Medium 字形的
# glyf 表级混排) 解决等宽字体中英文视觉密度差; 2026-09-17 移除混排, 直接指向
# 原版 Maple Mono NF CN —— wine 会自动扫描宿主字体 (prefix 的
# [Software\Wine\Fonts\External Fonts] 已登记 /run/host/fonts 下的各档),
# 因此无需往 prefix 拷贝任何字体文件。
read -r -d '' FONT_SUB_REG <<'EOF' || true
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Microsoft YaHei"="Maple Mono NF CN"
"Microsoft YaHei UI"="Maple Mono NF CN"
"微软雅黑"="Maple Mono NF CN"
"SimSun"="Maple Mono NF CN"
"宋体"="Maple Mono NF CN"
"NSimSun"="Maple Mono NF CN"
"新宋体"="Maple Mono NF CN"
"SimHei"="Maple Mono NF CN"
"黑体"="Maple Mono NF CN"
"Segoe UI"="Maple Mono NF CN"
"Arial"="Maple Mono NF CN"
"Tahoma"="Maple Mono NF CN"
"Calibri"="Maple Mono NF CN"
"Verdana"="Maple Mono NF CN"
"Microsoft Sans Serif"="Maple Mono NF CN"
"MS Shell Dlg"="Maple Mono NF CN"
"MS Shell Dlg 2"="Maple Mono NF CN"
"System"="Maple Mono NF CN"
EOF

ensure_fonts() {
  # 混排方案退役的一次性清理: 删掉旧 Hybrid 字体文件 (自检不关心文件, 但留着
  # 会让 wine 继续枚举一个已无引用的字体, 白占 prefix 空间)。幂等, 不存在即跳过。
  local fonts_dir="$PREFIX/windows/Fonts"
  rm -f "$fonts_dir/MapleMonoHybrid-Regular.ttf" "$fonts_dir/MapleMonoHybrid-Bold.ttf"

  if grep -q '"Microsoft YaHei"="Maple Mono NF CN"' "$BOTTLE_DIR/system.reg" 2>/dev/null; then
    log "字体替换注册表已就位, 跳过"
  else
    log "导入字体替换注册表"
    printf '%s\n' "$FONT_SUB_REG" | import_reg fontsub.reg
  fi
}

main() {

  if ! flatpak info --system com.usebottles.bottles >/dev/null 2>&1; then
    log "Bottles (Flatpak) 未安装, 跳过 —— 由 flatpak-apps 服务负责补装"
    return 0
  fi
  if [ ! -f "$BOTTLE_DIR/bottle.yml" ]; then
    log "未找到 bottle「$BOTTLE_NAME」($BOTTLE_DIR), 跳过 —— 需先在 Bottles 里创建并装好企业微信"
    return 0
  fi
  # 企业微信运行中时改 runner 会打断会话。不阻塞等待 (会拖垮 activate),
  # 直接跳过 —— 由 unit 的定时器在用户退出后重试收敛。
  if pgrep -f 'WXWork.exe' >/dev/null 2>&1; then
    log "企业微信运行中, 本轮跳过 (定时器会在退出后重试)"
    return 0
  fi

  ensure_runner || true
  ensure_policy || true
  ensure_fonts || true
}

main
