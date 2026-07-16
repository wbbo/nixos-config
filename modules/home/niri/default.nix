# 部署 Niri 配置文件到 ~/.config/niri/config.kdl
# 同时提供一个 polkit-gnome 认证代理 wrapper,供 Niri 启动时拉起(图形授权对话框)。
{ pkgs, ... }:
let
  polkit-gnome-agent = pkgs.writeShellScriptBin "polkit-gnome-authentication-agent-1" ''
    exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 "$@"
  '';
in
{
  home.packages = [ polkit-gnome-agent ];

  xdg.configFile."niri/config.kdl".source = ./config.kdl;
  xdg.configFile."niri/rule.kdl".source = ./rule.kdl;
  xdg.configFile."niri/binds.kdl".source = ./binds.kdl;
}
