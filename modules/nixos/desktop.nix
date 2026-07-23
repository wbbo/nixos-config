# 桌面:Niri 合成器 + Noctalia Shell(替代 waybar/mako/awww)
# 参考 nixos-niri-noctalia 项目方案
{ pkgs, ... }:
{
  ### Niri —— scrollable-tiling Wayland 合成器
  programs.niri.enable = true;

  # polkit 认证守护进程
  security.polkit.enable = true;

  ### 不启用 X11(纯 Wayland)
  services.xserver.enable = false;

  ### xdg desktop portal
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  ### Wayland 会话环境变量
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_SESSION_TYPE = "wayland";
    GDK_BACKEND = "wayland";
    TERMINAL = "kitty";
    TERM = "kitty";
    QT_QPA_PLATFORMTHEME = "qt6ct";
  };

  ### 光标主题(参考 nixos-niri-noctalia)
  environment.variables = {
    XCURSOR_THEME = "Bibata-Modern-Ice";
    XCURSOR_SIZE = "24";
  };
}
