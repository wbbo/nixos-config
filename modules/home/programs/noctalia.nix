# noctalia 配置 —— 壁纸 (官方插件) + 顶栏样式 + GTK 明暗同步
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
    # 视频壁纸官方插件 (noctalia/mpvpaper) 运行时依赖: mpvpaper 播放 + mpv;
    # socat 供插件跟踪 mpv IPC (幻灯片高亮/末帧抽取同步), ffmpeg 供末帧抽取
    pkgs.mpvpaper
    pkgs.mpv
    pkgs.ffmpeg
    pkgs.socat
    # 动态壁纸播放中切静态壁纸的桥接: mpvpaper 播放时主壁纸层被撤下 (插件
    # 设计), 单纯 wallpaper-set 视觉无效。本钩子在检测到视频在播时先
    # clear-all 再把所选静态图设回去 = "切静态壁纸即退出动态壁纸"。
    # 防递归/防误杀: 插件播放与切换时会把末帧图 set 回主壁纸 (取色用),
    # 路径全部落在 ~/.cache/noctalia/mpvpaper/ 下 (两种命名: <connector>_static.jpg
    # 与 <路径转写>.jpg, 后者不以 _static 结尾) —— 按目录前缀统一放行,
    # 否则选视频起播的末帧回填会被误判为手动切图, 视频刚起就被钩子杀掉
    # (实测: 桌面只剩末帧, 且插件状态错位堆积多个 mpvpaper 进程)。
    # 检测播放用 pgrep -f "bin/mpvpaper": 插件经 nixpkgs wrapper 启动,
    # 进程 comm 是 ".mpvpaper-wrapp", pgrep -x mpvpaper 永不匹配 (实测踩坑);
    # -f 匹配 cmdline 只命中播放器本体 (mpv 子进程 cmdline 不含 bin/mpvpaper)。
    (pkgs.writeShellApplication {
      name = "wallpaper-video-guard";
      runtimeInputs = [ pkgs.procps ];
      text = ''
        p="''${NOCTALIA_WALLPAPER_PATH,,}"
        case "$p" in
          */noctalia/mpvpaper/*) exit 0 ;;
          *.mp4|*.webm|*.mkv|*.mov|*.gif|*.avi|*.m4v) exit 0 ;;
        esac
        pgrep -f "bin/mpvpaper" >/dev/null 2>&1 || exit 0
        noctalia msg plugin noctalia/mpvpaper:service all clear-all
        noctalia msg wallpaper-set "''${NOCTALIA_WALLPAPER_PATH}"
      '';
    })
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
    # 关闭: automation 轮换与手动切图在 wallpaper_changed 钩子层面无来源
    # 标识, 保留它会让视频播放期间定时轮换误触发 "停视频换图" (钩子无法
    # 区分); 且轮换的静态图被视频层盖住本就不可见。静态图固定一张, 想换
    # 走设置面板 (会经 wallpaper-video-guard 停视频并应用所选图)。
    enabled = false
    interval_seconds = 1800
    order = "random"
    recursive = true

    # ============================================================
    # shell 全局字体 (通知/启动器/控制中心/锁屏等所有 Noctalia UI)
    # ============================================================
    [shell]
    font_family = "Maple Mono NF CN"

    # ============================================================
    # 会话菜单 (binds.kdl Ctrl+Alt+L → panel-toggle session)
    # actions 数组整体替换 noctalia 默认列表 (lock/logout/lock_and_suspend/
    # reboot/shutdown), 故逐项声明并在中间插入"休眠"。
    # 休眠无内置动作, 用 command 类型: 先锁屏再休眠 (与 lock_and_suspend
    # 语义一致, 恢复后需密码; sleep 2 等锁屏就绪)。sudo hibernate-now
    # (sudoers 已放行 mainUser 免密) 直写内核 S4 绕过 systemd 260 休眠栈
    # (详见 boot.nix), 锁屏后点按即休眠、无交互弹窗。
    # ============================================================
    [shell.session]
    [[shell.session.actions]]
    action = "lock"
    shortcut = "1"

    [[shell.session.actions]]
    action = "logout"
    shortcut = "2"

    [[shell.session.actions]]
    action = "lock_and_suspend"
    shortcut = "3"

    [[shell.session.actions]]
    action = "command"
    command = "noctalia msg session lock && sleep 2 && sudo hibernate-now"
    label = "休眠"
    glyph = "hibernate"
    shortcut = "4"

    [[shell.session.actions]]
    action = "reboot"
    shortcut = "5"

    [[shell.session.actions]]
    action = "shutdown"
    variant = "destructive"
    shortcut = "6"

    # ============================================================
    # 顶栏 bar
    # ============================================================
    [bar.default]
    enabled = true
    font_family = "Maple Mono NF CN"
    position = "top"
    thickness = 18
    background_opacity = 0.0   # 纯透明背景 (无毛玻璃由 niri layer-rule blur false 保证)
    border_width = 0.0
    shadow = false
    margin_ends = 4   # 两端边距 (bar 距屏幕左右边缘)
    margin_edge = 4   # 边缘边距 (bar 距屏幕上/下边缘)
    auto_hide = true  # 自动隐藏: 鼠标移出后隐藏
    # smart_auto_hide = false  # 智能: 活动工作区有窗口时隐藏, 空时显示
    # show_on_workspace_switch = true  # 与 auto_hide 配合: 切换工作区时短暂显示
    # auto_hide 只隐藏视觉、不联动 exclusive zone (Noctalia 5.0.0 源码
    # shouldReserveExclusiveZone 仅看 reserveSpace, auto_hide 不参与),
    # 故设 reserve_space=false 让 bar 走 overlay (exclusive zone=0):
    # 窗口始终占满全屏, bar 浮动在顶部, 隐藏时窗口不会被预留空间顶开。
    reserve_space = false
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
    end = ["media", "tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness"]
    # 视频壁纸: bar 不放按钮, picker 由 Mod+W 唤出 (见 binds.kdl);
    # 插件配置见下方 [plugins] 段。

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
    drawer = true  # 托盘图标默认收进抽屉, 点击展开

    # ============================================================
    # 视频壁纸 (noctalia/mpvpaper 官方插件) —— 动态背景 + 帧取色
    # 插件由 Noctalia 运行时从官方插件仓库拉取 (plugins source official)。
    # extract_last_frame: 停止/暂停时抽视频末帧设为 Noctalia 壁纸 → M3 取色
    # → 全生态 (fcitx/kitty/菜单) 随视频帧变色。视频放入
    # ${mainUser}/wallpaper/video/, Mod+W (binds.kdl) 唤出官方 picker 选视频。
    # 图片壁纸走 Noctalia 设置内的壁纸选择器 (automation 30min 轮换照常)。
    # ============================================================
    [plugins]
    enabled = ["noctalia/mpvpaper"]

    [plugin_settings."noctalia/mpvpaper"]
    video_directory = "/home/${mainUser}/wallpaper/video"
    mute = true
    extract_last_frame = true

    # GTK 明暗跟随 + 动态壁纸切静态桥接
    [hooks]
    theme_mode_changed = ["theme-sync"]   # 注意: home-manager 包在 /etc/profiles, 非 ~/.nix-profile
    wallpaper_changed = ["wallpaper-video-guard"]   # 播放中切静态壁纸 → 停视频并应用所选图
  '';
}
