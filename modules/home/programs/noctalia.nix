# noctalia 配置 —— 壁纸 + 顶栏样式 + 分辨率切换按钮
{ pkgs, noctalia, mainUser, ... }:
{
  # 显示设置按钮: 分辨率/缩放 合并到一个菜单 (res-menu: niri msg + fuzzel 两级)
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

        # 第一级: 分辨率 / 缩放
        ACT=$(printf '分辨率\n缩放\n' | fuzzel --dmenu --prompt "显示设置: ")
        case "$ACT" in
          分辨率)
            # 列出全部可用模式, 按面积降序 (首项=最大), 默认选中首项
            MODES=$(printf '%s\n' "$OUT" | sed -n '/Available modes:/,$p' | sed '1d' | sed -E 's/^[[:space:]]*([0-9]+x[0-9]+).*/\1/' | sort -u -t x -k1,1nr -k2,2nr)
            CHOICE=$(printf '%s\n' "$MODES" | fuzzel --dmenu --select-index=0 --prompt "分辨率 (当前 ''${CUR:-?}): ")
            # 切换即时生效 + 写入持久化 state (重启由 niri-apply-resolution 应用)
            [ -n "$CHOICE" ] && NIRI_SOCKET="$SOCK" niri msg output "$NAME" mode "$CHOICE" && echo "$CHOICE" > "$HOME/.local/state/niri-resolution"
            ;;
          缩放)
            # 显示百分比, 选择后转浮点 (如 125% → 1.25) 传给 niri
            CHOICE=$(printf '%s\n' '100%' '125%' '150%' '200%' '300%' | fuzzel --dmenu --prompt "缩放比例: ")
            [ -n "$CHOICE" ] || exit 0
            SCALE=$(printf '%s' "$CHOICE" | tr -d '%' | awk '{print $1/100}')
            NIRI_SOCKET="$SOCK" niri msg output "$NAME" scale "$SCALE" && echo "$SCALE" > "$HOME/.local/state/niri-scale"
            ;;
        esac
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
    background_opacity = 0.0   # 纯透明背景 (无毛玻璃由 niri layer-rule blur false 保证)
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
    # 显示设置按钮 —— 分辨率/缩放 合并菜单 (res-menu: 两级 fuzzel)
    # ============================================================
    [widget.display]
    type    = "custom_button"
    glyph   = "aspect-ratio"
    tooltip = "显示设置"
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
