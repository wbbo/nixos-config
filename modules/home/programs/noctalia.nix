# noctalia 配置 —— 壁纸 + 顶栏样式
{ noctalia, ... }:
{
  home.activation.createWallpaperDir = ''
    mkdir -p /home/wbb/wallpaper
    cp -n ${noctalia.packages.x86_64-linux.default}/share/noctalia/assets/noctalia-wallpaper.png /home/wbb/wallpaper/ || true
  '';

  xdg.configFile."noctalia/config.toml".text = ''
    # ============================================================
    # 壁纸
    # ============================================================
    [wallpaper]
    enabled = true
    directory = "/home/wbb/wallpaper"
    fill_color = "#26233a"
    transition_on_startup = true

    [wallpaper.default]
    path = "/home/wbb/wallpaper/noctalia-wallpaper.png"

    [wallpaper.automation]
    enabled = true
    interval_seconds = 1800
    order = "random"
    recursive = true

    # ============================================================
    # 顶栏 —— 全宽、半透明、悬浮胶囊风格
    # ============================================================
    [bar.default]
    position = "top"
    thickness = 38
    background_opacity = 0.0
    border_width = 0.0
    shadow = false
    margin_ends = 0
    margin_edge = 8
    padding = 12
    widget_spacing = 4
    radius = 0
    concave_edge_corners = false

    # 胶囊默认样式 (所有 widget 统一)
    capsule = true
    capsule_fill = "surface"
    capsule_opacity = 0.65
    capsule_radius = 10.0
    capsule_thickness = 0.76
    capsule_padding = 10

    start = ["launcher", "wallpaper", "workspaces"]
    center = ["clock"]
    end = ["media", "tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "control-center", "session"]
  '';
}
