# 部署 Niri 配置文件到 ~/.config/niri/
# 同时提供一个 polkit-gnome 认证代理 wrapper,供 Niri 启动时拉起(图形授权对话框)。
{ pkgs, lib, ... }:
let
  polkit-gnome-agent = pkgs.writeShellScriptBin "polkit-gnome-authentication-agent-1" ''
    exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 "$@"
  '';

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
in
{
  home.packages = [ polkit-gnome-agent niri-apply-resolution eye-care ];

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
