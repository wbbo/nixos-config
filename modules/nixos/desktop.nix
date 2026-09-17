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

  ### xdg desktop portal (gnome + gtk)
  # gnome portal 供 ScreenCast —— niri 实现 Mutter ScreenCast 的 D-Bus 接口喂它
  # (niri 的 nixpkgs 模块已自动把 xdg-desktop-portal-gnome 加进 extraPortals,
  # 上游注明 "required for screencast support"; 这里显式重复列出仅为可读性,
  # list 选项合并后 symlink join 去重, 无副作用)。
  # 所有 portal 屏幕共享走它: RustDesk 被控 / Flatpak OBS 屏幕捕获 / 浏览器共屏。
  # 原先列的 xdg-desktop-portal-wlr 已移除 —— niri 自带的 niri-portals.conf 是
  # default=gnome;gtk, wlr 不会被选中, 属多余项 (它不是任何功能的依赖)。
  # gtk 负责文件选择器等基础接口 (niri 模块要求 gtk 存在)。
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
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

  ### 图片的默认处理器 —— 显式钉死 imv-dir (见 packages.nix 的 imv 条目)
  # 与上一条**同源**的坑: 不显式声明时 xdg 按 desktop 文件名兜底, 而
  # imv-dir.desktop 字母序排在 imv.desktop 之前 ('-' 0x2D < '.' 0x2E) 因而
  # 胜出 —— 装 imv 后实测 17 个类型全部落到它头上。但这是**碰巧**: 任何新装
  # 的包只要带一个字母序更靠前的 image/* 声明就会静默抢走, 与当年
  # kitty-open.desktop 抢走 inode/directory 是同一个机制。
  # 17 条逐一镜像 imv-dir.desktop 的 MimeType 声明 (mimeapps.list 不支持
  # image/* 通配, 只能枚举; 规则 = "imv-dir 声明什么就给它什么")。含
  # image/svg+xml: imv 经 librsvg 后端能渲染静态 SVG (无动画/交互)。
  # **行为**: imv-dir <file> 展开为 imv -n <file> <dirname> —— 双击一张图 =
  # 打开其所在文件夹作播放列表并选中该张 (可左右翻页), 非单图单窗。
  # 想换看图器改这里; 用户级 ~/.config/mimeapps.list 优先级更高,
  # Nautilus "属性 → 打开方式 → 设为默认" 写入该文件即覆盖本钉死。
  # 注: xcf/psd/cr2 等 imv 不支持的类型不在覆盖范围, 仍无默认处理器。
  xdg.mime.defaultApplications = {
    "image/x-farbfeld" = "imv-dir.desktop";
    "image/tiff" = "imv-dir.desktop";
    "image/tiff-fx" = "imv-dir.desktop";
    "image/png" = "imv-dir.desktop";
    "image/x-png" = "imv-dir.desktop";
    "image/jpeg" = "imv-dir.desktop";
    "image/jpg" = "imv-dir.desktop";
    "image/pjpeg" = "imv-dir.desktop";
    "image/svg+xml" = "imv-dir.desktop";
    "image/gif" = "imv-dir.desktop";
    "image/bmp" = "imv-dir.desktop";
    "image/x-bmp" = "imv-dir.desktop";
    "image/heif" = "imv-dir.desktop";
    "image/avif" = "imv-dir.desktop";
    "image/jxl" = "imv-dir.desktop";
    "image/webp" = "imv-dir.desktop";
    "image/qoi" = "imv-dir.desktop";
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
    # SDL 视频后端: wayland 优先, 失败回退 X11 (经 xwayland-satellite)。
    # 原为纯 "wayland" —— 该写法禁止回退, SDL 应用 (Steam 等) 一旦 Wayland
    # 初始化不顺就直接失败而非降级。Steam 日志里有明确警告:
    #   SDL_VIDEODRIVER='wayland' does not allow fallback, use 'wayland,x11'
    SDL_VIDEODRIVER = "wayland,x11";
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