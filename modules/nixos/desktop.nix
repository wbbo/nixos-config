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

  ### xdg desktop portal (Wayland 合成器需要 wlr + gtk 双 portal)
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-wlr
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  ### Wayland 会话环境变量
  environment.sessionVariables = {
    XDG_CURRENT_DESKTOP = "niri:sway";
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_SESSION_TYPE = "wayland";
    GDK_BACKEND = "wayland";
    TERMINAL = "kitty";
    TERM = "kitty";
    SDL_VIDEODRIVER = "wayland";
    XCURSOR_THEME = "Bibata-Modern-Ice";
    XCURSOR_SIZE = "24";
  };

  ### Qt Wayland 插件
  # qt6ct 已从 nixpkgs 移除 (上游放弃维护).
  # Qt 应用主题由 GTK3 接管 (QT_QPA_PLATFORMTHEME=gtk3), 与 Noctalia 统一配色.
  # Kvantum 已移除 —— 在 gtk3 平台主题下不会被激活, 无需保留.
  environment.systemPackages = with pkgs; [
    qt6.qtwayland
  ];
}