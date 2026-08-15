# noctalia 配置 —— 壁纸 + 顶栏样式 + 分辨率切换按钮
{ pkgs, noctalia, mainUser, ... }:
{
  # 分辨率切换: 列出全部可用模式, 默认选中最大分辨率 (配合 [widget.display] 按钮)
  home.packages = [
    (pkgs.writeShellApplication {
      name = "res-menu";
      runtimeInputs = [ pkgs.niri pkgs.fuzzel ];
      text = ''
        err() { noctalia msg notification-show "res-menu: $1" 2>/dev/null || true; exit 1; }
        SOCK=$(find /run/user/"$(id -u)" -maxdepth 1 -name 'niri.wayland-1.*.sock' -print -quit 2>/dev/null)
        [ -n "$SOCK" ] || err "未找到 niri socket"
        OUT=$(NIRI_SOCKET="$SOCK" niri msg outputs 2>/dev/null) || err "niri msg 失败"
        NAME=$(printf '%s\n' "$OUT" | sed -n 's/.*(\(.*\)).*/\1/p' | head -1)
        CUR=$(printf '%s\n' "$OUT" | grep -m1 'Current mode' | sed -E 's/.*: ([0-9]+x[0-9]+).*/\1/')
        # 列出全部可用模式, 按面积降序 (首项=最大), 默认选中首项
        MODES=$(printf '%s\n' "$OUT" | sed -n '/Available modes:/,$p' | sed '1d' | sed -E 's/^[[:space:]]*([0-9]+x[0-9]+).*/\1/' | sort -u -t x -k1,1nr -k2,2nr)
        CHOICE=$(printf '%s\n' "$MODES" | fuzzel --dmenu --select-index=0 --prompt "分辨率 (当前 ''${CUR:-?}): ")
        [ -n "$CHOICE" ] && NIRI_SOCKET="$SOCK" niri msg output "$NAME" mode "$CHOICE"
      '';
    })
  ];

  home.activation.createWallpaperDir = ''
    mkdir -p /home/${mainUser}/wallpaper
    cp -n ${noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/noctalia/assets/noctalia-wallpaper.png /home/${mainUser}/wallpaper/ || true
  '';

  xdg.configFile."noctalia/config.toml".text = ''
    [theme]
    source = "wallpaper"
    # ============================================================
    # 壁纸
    # ============================================================
    [wallpaper]
    enabled = true
    directory = "/home/${mainUser}/wallpaper"
    fill_color = "#26233a"
    transition_on_startup = true

    [wallpaper.default]
    path = "/home/${mainUser}/wallpaper/noctalia-wallpaper.png"

    [wallpaper.automation]
    enabled = true
    interval_seconds = 1800
    order = "random"
    recursive = true

    # ============================================================
    # 顶栏 bar
    # ============================================================
    [bar.default]
    enabled = true
    font_family = "Maple Mono NF CN"
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
    capsule_opacity = 0
    # capsule_radius = auto
    capsule_thickness = 0.76
    capsule_padding = 10

    start = ["launcher", "workspaces"]
    center = ["clock"]
    end = ["media", "tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "display"]

    # ============================================================
    # 分辨率切换按钮 —— 点击弹出 1K/2K/4K 菜单 (res-menu: niri msg + fuzzel)
    # ============================================================
    [widget.display]
    type    = "custom_button"
    glyph   = "aspect-ratio"
    tooltip = "分辨率"
    command = "res-menu"

    # ============================================================
    # 网络 widget —— 只显示图标 (网卡名称在悬浮提示中)
    # ============================================================
    [widget.network]
    show_label = false

    # ============================================================
    # 时钟 (center) —— yyyy-MM-dd HH:mm:ss
    # ============================================================
    [widget.clock]
    format = "{:%Y-%m-%d %H:%M:%S}"

    [location]
    auto_locate = true
    [widget.tray]
    drawer = false
  '';
}
