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

  ### 目录的默认处理器 —— 指向 Nautilus (见 packages.nix 的 nautilus 条目)
  # 不显式设置时 xdg 按 desktop 文件名兜底, 而 kitty 自带的
  # kitty-open.desktop 同样声明了 inode/directory 且字母序靠前 —— 实测
  # `xdg-mime query default inode/directory` 返回 kitty-open.desktop, 后果是
  # 从浏览器点"打开所在文件夹"拉起 kitty 而非文件管理器。
  # 用系统级 xdg.mime.* (写 /etc/xdg/mimeapps.list) 而非 HM 的 xdg.mimeApps:
  # 后者会接管 ~/.config/mimeapps.list, 覆盖用户手工维护的条目 (Thunderbird
  # 的 mailto/message-rfc822 关联); 系统级文件优先级更低, 仅在用户级没有该
  # MIME 的条目时补缺, 零风险。
  # 注: 文件名是 org.gnome.Nautilus.desktop (Nautilus 50 的正式 desktop id,
  # 无 nautilus.desktop 别名, 写错则静默无效)。
  xdg.mime.defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";

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