# noctalia 配置 —— 壁纸 + 顶栏样式 + 分辨率切换按钮 + GTK 明暗同步
{ pkgs, noctalia, mainUser, lib, ... }:
let
  # GTK 明暗跟随 Noctalia 主题模式 (由 config.toml [hooks].theme_mode_changed 触发)
  # NixOS 打包: store 可执行, home.packages 装到 ~/.nix-profile/bin/theme-sync
  theme-sync = pkgs.writeShellApplication {
    name = "theme-sync";
    runtimeInputs = [ pkgs.glib pkgs.gsettings-desktop-schemas ];
    text = ''
      # gsettings 需能读到 org.gnome.desktop.interface schema
      export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
      MODE=$(noctalia msg theme-mode-get 2>/dev/null || echo dark)
      if [ "$MODE" = "light" ]; then
        SCHEME="prefer-light"; GTK="adw-gtk3"; PREFER_DARK="false"
      else
        SCHEME="prefer-dark"; GTK="adw-gtk3-dark"; PREFER_DARK="true"
      fi
      gsettings set org.gnome.desktop.interface color-scheme "$SCHEME" 2>/dev/null || true
      gsettings set org.gnome.desktop.interface gtk-theme "$GTK" 2>/dev/null || true
      # GTK3 prefers-color-scheme (Firefox 等 GTK3 应用读 settings.ini)
      mkdir -p "$HOME/.config/gtk-3.0"
      printf '[Settings]\ngtk-application-prefer-dark-theme=%s\n' "$PREFER_DARK" > "$HOME/.config/gtk-3.0/settings.ini"
    '';
  };
in {
  # 显示设置按钮: 分辨率/缩放 合并到一个菜单 (res-menu: niri msg + fuzzel 两级)
  home.packages = [
    theme-sync
    # 视频壁纸插件依赖 (noctalia/mpvpaper): mpvpaper 播放 + mpv 抽帧
    pkgs.mpvpaper
    pkgs.mpv
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
    mkdir -p /home/${mainUser}/wallpaper/video
    cp -n ${noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/noctalia/assets/noctalia-wallpaper.png /home/${mainUser}/wallpaper/ || true
  '';

  xdg.configFile."noctalia/config.toml".text = ''
    [theme]
    source = "wallpaper"
    # muted: 低饱和柔和取色 (其余可选 m3-content/m3-tonal-spot/vibrant 等)
    wallpaper_scheme = "muted"

    # 模板渲染: kitty/qt 动态取色 + fcitx NyxMellow 皮肤 (方案 A)。
    # 刻意不含 starship: Noctalia 渲染 starship 会覆盖自定义 powerline palette (colors),
    # 导致 format 引用的 color_* 失效 → 无彩色。starship.toml 完全由 home-manager
    # 声明式管理 (见 starship.nix)。
    # nyxmellow 模板由 fcitx5.nix 部署到 ~/.local/share/fcitx5/themes/nyxmellow/templates/,
    # 渲染后 fcitx5 重启生效 (post_hook)。
    [theme.templates]
    builtin_ids = ["kitty", "qt"]

    [theme.templates.user.nyxmellow_theme]
    input_path = "/home/${mainUser}/.local/share/fcitx5/themes/nyxmellow/templates/theme.conf"
    output_path = "/home/${mainUser}/.local/share/fcitx5/themes/nyxmellow/theme.conf"

    [theme.templates.user.nyxmellow_panel]
    input_path = "/home/${mainUser}/.local/share/fcitx5/themes/nyxmellow/templates/panel.svg"
    output_path = "/home/${mainUser}/.local/share/fcitx5/themes/nyxmellow/panel.svg"

    [theme.templates.user.nyxmellow_highlight]
    input_path = "/home/${mainUser}/.local/share/fcitx5/themes/nyxmellow/templates/highlight.svg"
    output_path = "/home/${mainUser}/.local/share/fcitx5/themes/nyxmellow/highlight.svg"
    post_hook = "systemctl --user restart app-org.fcitx.Fcitx5@autostart.service 2>/dev/null || { pkill -f 'bin/fcitx5' 2>/dev/null; sleep 1; fcitx5 -d >/dev/null 2>&1 & }"
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
    # shell 全局字体 (通知/启动器/控制中心/锁屏等所有 Noctalia UI)
    # ============================================================
    [shell]
    font_family = "Maple Mono NF CN"

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
    end = ["media", "tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "display", "mpvpaper"]

    # ============================================================
    # 显示设置按钮 —— 分辨率/缩放 合并菜单 (res-menu: 两级 fuzzel)
    # ============================================================
    [widget.display]
    type    = "custom_button"
    glyph   = "aspect-ratio"
    tooltip = "显示设置"
    left    = "exec res-menu"   # 新版: command 已改为 left gesture binding

    # 视频壁纸控制 widget (noctalia/mpvpaper 插件): 点击打开 picker 选视频/切换/停止
    [widget.mpvpaper]
    type  = "noctalia/mpvpaper:mpvpaper"
    glyph = "movie"

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

    # ============================================================
    # 视频壁纸 (noctalia/mpvpaper 插件) —— 动态背景 + 帧取色
    # 插件由 Noctalia 运行时从官方插件仓库拉取 (plugins source official)。
    # extract_last_frame: 插件用 ffmpeg 抽视频帧, 经 noctalia.setWallpaper
    # 设为 Noctalia 壁纸 → M3 取色 → 全生态 (fcitx/kitty/菜单) 随视频帧变色。
    # 视频放入 ${mainUser}/wallpaper/video/ 即自动生效 (可在设置里切换)。
    # ============================================================
    [plugins]
    enabled = ["noctalia/mpvpaper"]

    [plugin_settings."noctalia/mpvpaper"]
    video_directory = "/home/${mainUser}/wallpaper/video"
    mute = true
    extract_last_frame = true

    # GTK 明暗跟随: Noctalia 切换明暗时同步 GSettings + GTK3 settings.ini (libadwaita/GTK/Firefox)
    [hooks]
    theme_mode_changed = ["theme-sync"]   # 注意: home-manager 包在 /etc/profiles, 非 ~/.nix-profile
  '';
}
