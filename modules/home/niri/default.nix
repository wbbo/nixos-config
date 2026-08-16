# 部署 Niri 配置文件到 ~/.config/niri/config.kdl
# 同时提供一个 polkit-gnome 认证代理 wrapper,供 Niri 启动时拉起(图形授权对话框)。
{ pkgs, ... }:
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
in
{
  home.packages = [ polkit-gnome-agent niri-apply-resolution ];

  xdg.configFile."niri/config.kdl".source = ./config.kdl;
  xdg.configFile."niri/rule.kdl".source = ./rule.kdl;
  xdg.configFile."niri/binds.kdl".source = ./binds.kdl;
}
