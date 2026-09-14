# 部署 Niri 配置文件到 ~/.config/niri/
# xwayland-satellite: X11 兼容层 (Steam/老应用), niri 26.04+ 检测到它在 PATH
# 即按需自动 spawn (on-demand, 无 X11 客户端时零资源); 缺它则 X11 应用无法运行。
{ pkgs, lib, ... }:
let
  # 应用持久化的输出设置: niri-res / Noctalia 顶栏修改时写入
  # ~/.local/state/niri-resolution|niri-scale, 本脚本由 config.kdl
  # spawn-at-startup 调用, 启动时覆盖声明式默认。
  niri-apply-resolution = pkgs.writeShellScriptBin "niri-apply-resolution" ''
    set -e
    MODE="$HOME/.local/state/niri-resolution"
    SCALE="$HOME/.local/state/niri-scale"
    { [ -s "$MODE" ] || [ -s "$SCALE" ]; } || exit 0
    # 取第一个输出名 (Virtual-1 等)
    OUTPUT="$(${pkgs.gnugrep}/bin/grep -oP '^Output "\K[^"]+' < <(niri msg outputs 2>/dev/null) | head -1)"
    [ -n "$OUTPUT" ] || exit 0
    [ -s "$MODE" ]  && niri msg output "$OUTPUT" mode  "$(cat "$MODE")"  2>/dev/null || true
    [ -s "$SCALE" ] && niri msg output "$OUTPUT" scale "$(cat "$SCALE")" 2>/dev/null || true
  '';

  # 护眼模式: 切换 ~/.config/niri/effects.kdl 符号链接 (normal/eyecare 二选一)
  # + wlsunset 暖色温 + niri 重载。状态单一来源 = 符号链接目标 (跨重启存活)。
  # --sync: 启动对齐 (config.kdl spawn-at-startup 调用), 修复链接 + 同步 wlsunset。
  eye-care = pkgs.writeShellApplication {
    name = "eye-care";
    runtimeInputs = [ pkgs.wlsunset pkgs.libnotify pkgs.niri pkgs.coreutils ];
    text = ''
      set -uo pipefail
      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/nixos-eyecare.lock"
      flock -w 5 9 || exit 1

      NIRI_DIR="$HOME/.config/niri"
      LINK="$NIRI_DIR/effects.kdl"
      NORMAL="$NIRI_DIR/effects_normal.kdl"
      EYECARE="$NIRI_DIR/effects_eyecare.kdl"
      LOG="''${XDG_RUNTIME_DIR:-/tmp}/nixos-eyecare.log"
      TEMP=5500

      is_on() { [ "$(readlink "$LINK" 2>/dev/null)" = "$EYECARE" ]; }

      apply() {
        ln -sfn "$1" "$LINK"
        if ! niri msg action load-config-file >>"$LOG" 2>&1; then
          sleep 0.2
          niri msg action load-config-file >>"$LOG" 2>&1 || true
        fi
      }

      # 启动对齐: 修复缺失/损坏链接 + 同步 wlsunset 状态 (niri spawn-at-startup 调用)
      if [ "''${1:-}" = "--sync" ]; then
        if ! is_on && [ "$(readlink "$LINK" 2>/dev/null)" != "$NORMAL" ]; then
          ln -sfn "$NORMAL" "$LINK"
          niri msg action load-config-file >>"$LOG" 2>&1 || true
        fi
        pkill -x wlsunset 2>/dev/null || true
        if is_on && command -v wlsunset >/dev/null 2>&1; then
          # 9>&- 关闭锁 fd: 否则 wlsunset 继承 fd 9 永久持锁, 后续 eye-care flock 失败
          nohup wlsunset -T 6500 -t "$TEMP" -d 0.3 -S 00:00 -s 00:00 >/dev/null 2>&1 9>&- &
        fi
        exit 0
      fi

      if is_on; then
        apply "$NORMAL"
        pkill -x wlsunset 2>/dev/null || true
        notify-send -t 1500 "护眼模式: 关"
      else
        apply "$EYECARE"
        pkill -x wlsunset 2>/dev/null || true
        nohup wlsunset -T 6500 -t "$TEMP" -d 0.3 -S 00:00 -s 00:00 >/dev/null 2>&1 9>&- &
        notify-send -t 1500 "护眼模式: 开"
      fi
    '';
  };

  # 录屏切换 (Mod+Alt+R): 全屏 + 系统声音, NVENC 硬件编码。
  # 状态判据 = wf-recorder 进程是否存在; 输出路径记在 XDG_RUNTIME_DIR 的状态
  # 文件里, 停止时据此报出文件名。
  # 注: wf-recorder 是前台阻塞程序, 靠 SIGINT 收尾并写索引, 不能像截图那样
  # 一条命令跑完。故用 pkill -x 精确匹配进程名 —— 本会话踩过 pkill -f 把自身
  # 命令行也匹配上的坑。
  # -a 录 default sink 的 monitor (系统声音); 要录麦克风改用 -a <device>,
  # 设备名用 pactl list short sources 查。
  # 光标: wf-recorder 在 screencopy 调用点**硬编码** overlay_cursor=1
  # (main.cpp: zwlr_screencopy_manager_v1_capture_output(manager, 1, output)),
  # 即始终把鼠标指针画进画面, 且没有开关能关掉 (gsr 则提供 -cursor yes|no)。
  # 曾因"源码里搜不到 cursor 字样"误判为不录指针 —— 位置实参的字面量搜不到,
  # 字符串搜索只能证明存在、不能证明不存在。
  # 编码: 4090 的 h264_nvenc (nixpkgs 的 ffmpeg 已启用 nvenc)。画质不满意可加
  # -p preset=p5 -p cq=23 (编码器参数经 -p key=value 透传)。
  # 输出用 .mkv (Matroska) 而非 .mp4: mp4 的索引 (moov) 只在**正常收尾**时才写
  # 入文件末尾, 崩溃/断电/被 kill 都留下一个没索引、任何播放器都打不开的文件
  # (实测: 一段 1h46m 的 4K 录制因此差点全废, 靠 /proc/<pid>/fd 才抢回来)。
  # Matroska 按块落盘 (实测 ~2MB 一块, 3Mbps 下约 5 秒), 强杀后已落盘部分
  # ffprobe/mpv 均可正常读取, 最多丢最后一块; 代价是没有 trailer —— duration
  # 显示 N/A 且不能拖进度条 (正常停止的文件不受影响)。注意粒度: 总量不足
  # 一块的短录制 (约 40 秒内) 强杀仍会全丢。A/B 实测 (录 10 秒 kill -9):
  # mkv 6.3MB 落盘 → h264 可解码播放; mp4 7.6MB 落盘 → "moov atom not found"。
  # 分享需要 mp4 时 ffmpeg -i in.mkv -c copy out.mp4 无损转一下即可。
  # wf-recorder 按扩展名选封装器 (-f out.mkv → matroska)。
  record-toggle = pkgs.writeShellApplication {
    name = "record-toggle";
    runtimeInputs = [ pkgs.wf-recorder pkgs.libnotify pkgs.coreutils pkgs.procps ];
    text = ''
      set -uo pipefail
      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/nixos-record.lock"
      flock -w 5 9 || exit 1

      # 输出统一到 ~/Videos/record/ —— 录制工具 (wf-recorder / OBS) 共用
      # 这一个目录, 靠各自的文件名模式区分来源。
      # 在 ~/Videos 之下, 故持久化自动覆盖 —— persist.nix 只声明 Videos 顶层,
      # 子目录随之落盘。
      DIR="$HOME/Videos/record"
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/nixos-record.state"
      mkdir -p "$DIR"

      if pgrep -x wf-recorder >/dev/null 2>&1; then
        OUT="$(cat "$STATE" 2>/dev/null || true)"
        pkill -INT -x wf-recorder
        # 等它真正写完索引再报"已保存": 固定 sleep 1 在长录制下可能提前宣告成功
        # (且此时 pgrep 判据仍为真, 紧接着再按会被当成"正在录制"而非"停止")。
        for _ in $(seq 20); do
          pgrep -x wf-recorder >/dev/null 2>&1 || break
          sleep 0.5
        done
        rm -f "$STATE"
        if [ -n "$OUT" ]; then
          notify-send -t 3000 "录屏已停止" "已保存: $(basename "$OUT")"
        else
          notify-send -t 3000 "录屏已停止"
        fi
        exit 0
      fi

      OUT="$DIR/rec-$(date +%F_%H-%M-%S).mkv"
      echo "$OUT" > "$STATE"

      # ---- 编码器协商 (按机器能力降级, 结果缓存至本次开机) ----
      # 本脚本是分发模板共享代码, 不同机器硬件不同: RTX 机器 NVENC 最快;
      # Intel 核显机器 VAAPI (本机 960M 因 Maxwell 不受驱动支持而刻意闲置,
      # 见 hosts/default/local.nix —— NVENC 依赖专有驱动, 在这类机器上
      # cuInit 报 CUDA_ERROR_NO_DEVICE, 曾致 Mod+Alt+R 弹出"开始录屏"通知
      # 却录不到任何东西); 都没有则 libx264 软编兜底。
      # 两段式判定:
      # 1. 前置条件零成本筛 —— NVENC 看 nvidia 内核模块是否在载 (专有驱动
      #    才提供 NVENC), VAAPI 看渲染节点是否存在;
      # 2. 命中者用 timeout 2.5s 实录探测确认 —— rc=124 (被 timeout 杀掉,
      #    即 2.5s 内一直在正常录制) = 可用; 提前自行退出 = 不可用。
      #    ⚠ 不能用「存活 N 秒」做判据: nvenc 失败并非瞬时 —— cuInit 报错
      #    后要 ~4s 才退出 (实测), 存活性判据会把它误判成可用并缓存
      #    (2026-09-14 实际踩过: 缓存了 nvenc, 之后每次录制全部失败)。
      # 探测进程必须带 9>&-, 否则会把 flock 带走 (见下方同一个坑)。
      ENCFILE="''${XDG_RUNTIME_DIR:-/tmp}/nixos-record.encoder"
      ENC="$(cat "$ENCFILE" 2>/dev/null || true)"
      if [ -z "$ENC" ]; then
        ENC=libx264  # 兜底
        for cand in h264_nvenc h264_vaapi; do
          case "$cand" in
            h264_nvenc) grep -q '^nvidia' /proc/modules 2>/dev/null || continue ;;
            h264_vaapi) ls /dev/dri/renderD128 >/dev/null 2>&1 || continue ;;
          esac
          PROBE="$DIR/.enc-probe.mkv"
          rm -f "$PROBE"
          rc=0
          timeout 2.5 wf-recorder -c "$cand" -f "$PROBE" 9>&- >/dev/null 2>&1 || rc=$?
          rm -f "$PROBE"
          if [ "$rc" = 124 ]; then
            ENC="$cand"
            break
          fi
        done
        echo "$ENC" > "$ENCFILE"
      fi

      notify-send -t 2000 "开始录屏" \
        "输出: $(basename "$OUT") · 编码器: $ENC (再按 Mod+Alt+R 停止)"
      # 9>&-: 关闭锁 fd —— 否则 wf-recorder 继承 fd 9 把锁一直带到录制结束, 期间
      # 每次按键都会卡在 flock -w 5 上然后 exit 1 静默退出 (表现为"按了没反应,
      # 停不下来"; 实测一段 1h46m 的录制就是这么停不掉的)。eye-care 的 wlsunset
      # 踩过同一个坑, 那里已用 9>&-。
      exec wf-recorder -c "$ENC" -a -f "$OUT" 9>&-
    '';
  };
in
{
  home.packages = [ niri-apply-resolution eye-care record-toggle pkgs.xwayland-satellite ];

  # force = true: 接管首启自动生成的官方默认 config.kdl
  # (全新安装首启 niri 会生成默认模板, 非 HM 链接; 无 force 时 HM clobber
  # 安全机制拒绝覆盖 → home-manager 激活失败, noctalia/fcitx5 等全部起不来)
  xdg.configFile."niri/config.kdl" = {
    force = true;
    source = ./config.kdl;
  };
  xdg.configFile."niri/rule.kdl".source = ./rule.kdl;
  xdg.configFile."niri/binds.kdl".source = ./binds.kdl;
  # 护眼模式的两个外观变体 (store 只读, 由 eye-care 符号链接切换)
  xdg.configFile."niri/effects_normal.kdl".source = ./effects_normal.kdl;
  xdg.configFile."niri/effects_eyecare.kdl".source = ./effects_eyecare.kdl;

  # 预建 effects.kdl 符号链接 -> normal: 冷启动时 config.kdl include 它必须已存在
  home.activation.initEyeCareEffects = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "$HOME/.config/niri/effects.kdl" ]; then
      ln -sfn "$HOME/.config/niri/effects_normal.kdl" "$HOME/.config/niri/effects.kdl"
    fi
  '';
}
