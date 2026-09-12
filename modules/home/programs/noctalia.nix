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
    # clear-all、等插件异步收尾完成后再把所选静态图 set 回去 = "切静态壁纸
    # 即退出动态壁纸"(clear-all 的异步竞态与 fix 细节见脚本内 ★ 注释)。
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
      runtimeInputs = [ pkgs.procps pkgs.coreutils ];
      text = ''
        p="''${NOCTALIA_WALLPAPER_PATH,,}"
        F="$HOME/.local/state/noctalia/settings.toml"

        # 开关静态轮播: settings.toml 对 config.toml 是按键覆盖 (实测), 只写
        # enabled 一个键, interval/order/recursive 继承 config.toml (改
        # noctalia.nix 即生效)。幂等且已同值则早退 —— 也防 config-reload
        # 触发的事件重入成环。原子替换避免与 noctalia 自身写入交错。
        set_automation() {
          [ -f "$F" ] || return 0
          local cur T
          cur="$(awk '/^\[wallpaper\.automation\]/{f=1;next} /^\[/{f=0} f&&/^enabled/{print $3}' "$F" 2>/dev/null || true)"
          # 注意必须用 if 而非 `[ ... ] && return 0`: 后者条件为假时整个 && 列表
          # 返回非零, 在 writeShellApplication 的 set -e 下直接终止整个钩子
          # (实测: 轮播开关失效, 钩子静默退出)
          if [ "$cur" = "$1" ]; then
            return 0
          fi
          T="$F.tmp.$$"
          if awk -v want="$1" '
                /^\[wallpaper\.automation\]/ { skip = 1; next }
                /^\[/ { skip = 0 }
                !skip { print }
                END { printf "\n[wallpaper.automation]\nenabled = %s\n", want }
              ' "$F" > "$T" 2>/dev/null; then
            mv "$T" "$F" 2>/dev/null || rm -f "$T"
          else
            rm -f "$T"
          fi
          noctalia msg config-reload >/dev/null 2>&1 || true
        }

        # 1) 插件自身的壁纸事件 (起播/停止时的末帧回填与 M3 取色):
        #    有 mpvpaper 进程 = 视频起播 → 关轮播 (定时轮换不再打断视频);
        #    无进程 = 视频已停 (picker Stop 或切静态) → 恢复轮播。
        #    时序依据 (插件源码): 起播先启进程后回填, 停止先杀进程后回填。
        case "$p" in
          */noctalia/mpvpaper/*)
            if pgrep -f "bin/mpvpaper" >/dev/null 2>&1; then
              set_automation false
            else
              set_automation true
            fi
            exit 0
            ;;
        esac

        # 2) 直接选中视频文件 —— 兜底放行 (起播本身由插件回填触发上面的分支)
        case "$p" in
          *.mp4|*.webm|*.mkv|*.mov|*.gif|*.avi|*.m4v) exit 0 ;;
        esac

        # 3) 视频在播 + 切静态图 = 用户手动切: 视频播放期间轮播已被关, 不存在
        #    自动轮换事件, 故此分支必为手动操作 → 停视频 → 应用所选图 → 恢复
        #    轮播。(若上面的关闭失败则退化为旧行为: 轮换误触发会停视频。)
        pgrep -f "bin/mpvpaper" >/dev/null 2>&1 || exit 0
        # ★ 竞态修复 (保留): clear-all 是异步的 (杀进程 → ffmpeg 抽帧回填 →
        #   恢复主壁纸层), 且视频播放期间主壁纸层被插件撤下 (managed by
        #   external source) —— 此刻的 wallpaper-set 只写 state、创建实例被
        #   屏蔽, 屏幕不变 (实测: applied 无 creating 日志)。回填晚到再把壁纸
        #   换成视频帧, 用户看到"切静态失败, 动态变静态"。故: 先 clear-all,
        #   等进程退出 + 回填/主层恢复落定, 再无条件 set 所选图 —— 此时主层
        #   已恢复, 才真正显示。set 触发的 wallpaper_changed 重入: 视频已死 →
        #   上方分支直接 exit, 无循环。
        noctalia msg plugin noctalia/mpvpaper:service all clear-all
        # 等 mpvpaper 进程退出 (上限 5s)
        i=0
        while pgrep -f "bin/mpvpaper" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do
          sleep 0.1
          i=$((i + 1))
        done
        # 插件异步收尾缓冲: 抽帧 (ffmpeg) + 回填 setWallpaper + 主层恢复
        sleep 1.5
        # extract_last_frame=false 下, clear-all 恢复主层时显示的已是所选图,
        # 通常无需再 set —— 重复 set 会多播一次过渡动画 (用户可见 "切两次":
        # 第一次末帧、第二次所选图)。仅当状态未落到目标图时兜底 set。
        cur="$(noctalia msg wallpaper-get 2>/dev/null || true)"
        if [ "$cur" != "$NOCTALIA_WALLPAPER_PATH" ]; then
          noctalia msg wallpaper-set "$NOCTALIA_WALLPAPER_PATH"
        fi
        set_automation true
        exit 0
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
    mkdir -p /home/${mainUser}/Pictures/Wallpapers/video
    cp -n ${noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/noctalia/assets/noctalia-wallpaper.png /home/${mainUser}/Pictures/Wallpapers/ || true
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
    # fcitx5 由 systemd 用户服务管理 (fcitx5.nix): 皮肤模板渲染后重启该服务生效。
    # --no-block: 不阻塞 Noctalia 渲染线程 (fcitx5 重启约 3-5 秒, 阻塞会卡 UI)。
    # 不要用 fcitx5 -d 兜底 —— 会创建绕过 systemd 的野实例 (单实例锁冲突源)。
    post_hook = "systemctl --user restart --no-block fcitx5.service"
    # ============================================================
    # 壁纸
    # ============================================================
    [wallpaper]
    enabled = true
    # Noctalia 默认壁纸目录 (原为 ~/wallpaper, 2026-09-12 整体迁入):
    # 图片轮播池 + video/ 子目录 (mpvpaper 插件) + 默认壁纸都在此树下,
    # 目录创建与默认壁纸投放由 home.activation.createWallpaperDir 保证。
    directory = "/home/${mainUser}/Pictures/Wallpapers"
    fill_color = "#26233a"
    transition_on_startup = true
    # 切换壁纸的过渡效果 —— 每次随机挑一种 (官方文档: array of effects
    # picked at random each transition; 省略此键 = 使用全部效果)。
    # 注意键名是单数 transition (写 transitions 会被校验为 unknown setting)。
    # 可选: fade / disc / honeycomb / stripes / wipe / zoom
    transition = ["fade", "wipe", "zoom", "disc", "stripes", "honeycomb"]
    transition_duration = 1500

    [wallpaper.default]
    path = "/home/${mainUser}/Pictures/Wallpapers/noctalia-wallpaper.png"

    [wallpaper.automation]
    # 静态壁纸每 interval_seconds 随机轮换一张 (与视频壁纸分开设置)。
    # 动态开关: 由 wallpaper-video-guard 钩子自动维护 (写 settings.toml 覆盖,
    # 该文件对 config.toml 是按键覆盖) ——
    #   视频起播 → enabled=false: 轮换不再打断视频, 同时消除"轮换 vs 手动切图"
    #     的来源歧义 (播放期间任何 wallpaper_changed 都必是手动操作);
    #   视频停止 / 手动切静态图 → enabled=true: 恢复轮换。
    # 因此无需 noctalia 暴露事件来源 (它只给 NOCTALIA_WALLPAPER_PATH/CONNECTOR)。
    # recursive=false: 实测 (2026-09-12, 55 次采样覆盖 43/44 张图、0 次命中
    # 视频) —— 轮换池按扩展名过滤, 即使递归也不会选中 video/ 里的 mp4; 视频
    # 只能经 mpvpaper 插件播放, 递归只会白扫 32MB。
    # order=random 实为洗牌后顺序遍历 (实测 30 次无重复), 非独立随机。
    enabled = true
    interval_seconds = 1800
    order = "random"
    recursive = false

    # ============================================================
    # shell 全局字体 (通知/启动器/控制中心/锁屏等所有 Noctalia UI)
    # ============================================================
    [shell]
    font_family = "Maple Mono NF CN"
    # 内建 polkit 认证代理 (替代 niri 原先 spawn 的 polkit-gnome): 弹窗风格
    # 统一, 且不再跑 GTK 认证进程。整个会话只能有一个 agent —— 故 config.kdl
    # 已移除 spawn-at-startup "polkit-gnome-authentication-agent-1"。
    # 它负责 reboot/poweroff/suspend、udisks2 挂载、flatpak 安装等图形授权。
    # 前置: 需 logind / XDG_SESSION_ID (Noctalia 内建检查), 本机 systemd+greetd 满足。
    polkit_agent = true
    # 密码框样式: random = 输入时显示随机小图标 (替代默认实心圆点),
    # 作用于所有密码输入场景 —— polkit 认证框、锁屏登录框等。
    # 取值仅 default / random 两个 (用 `noctalia config validate` 实测;
    # 注意: UI 选项名 filled-circles/random-icons 是翻译键, 不是配置值)。
    password_style = "random"

    # ============================================================
    # 会话菜单 (binds.kdl Mod+Alt+L → panel-toggle session)
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
    end = ["media", "tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "display"]
    # 视频壁纸: bar 不放按钮, picker 由 Mod+W 唤出 (见 binds.kdl);
    # 插件配置见下方 [plugins] 段。

    # ============================================================
    # 显示设置按钮 —— 分辨率/缩放 合并菜单 (res-menu: 两级 fuzzel)
    # 动作绑定必须是 [widget.X.actions] 表 (v5 gesture bindings);
    # 顶层 left = ... 不在 custom_button 的 Options 字段定义中, 被静默
    # 丢弃 —— 曾因此按钮点击无任何响应 (实测踩坑)。
    # ============================================================
    [widget.display]
    type    = "custom_button"
    glyph   = "aspect-ratio"
    tooltip = "显示设置"

    [widget.display.actions]
    left = "exec res-menu"

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

    # ============================================================
    # 空闲行为 (idle) —— 自动锁屏 + 自动关屏
    # 结构实证 (2026-09-12): `[idle.behavior.<名字>]` 表, 有效字段仅
    # action / timeout / locked_timeout / command / resume_command
    # (kind/name/type/preset 均报 unknown setting); 名字取表键名, 无 name 字段。
    # action 取值: lock / screen_off / suspend / custom (custom 配 command)。
    # 用 `noctalia config validate <file>` 可离线校验候选写法。
    # behavior_order 决定执行顺序 (TOML 表无序, 显式声明)。
    # ============================================================
    [idle]
    behavior_order = ["lock-screen", "screen-off"]
    # 触发前全屏渐暗秒数 (0 = 关闭); 兼作 "Idle Dim" 视觉预告
    pre_action_fade_seconds = 5

    [idle.behavior.lock-screen]
    action = "lock"
    timeout = 300          # 闲置 5 分钟 → 自动锁屏
    locked_timeout = 300

    [idle.behavior.screen-off]
    action = "screen_off"
    timeout = 600          # 闲置 10 分钟 → 关闭屏幕 (DPMS)
    locked_timeout = 600

    [location]
    auto_locate = true
    [widget.tray]
    drawer = true  # 托盘图标默认收进抽屉, 点击展开

    # ============================================================
    # 视频壁纸 (noctalia/mpvpaper 官方插件) —— 动态背景 + 帧取色
    # 插件由 Noctalia 运行时从官方插件仓库拉取 (plugins source official)。
    # extract_last_frame: 停止/暂停时抽视频末帧设为 Noctalia 壁纸 → M3 取色
    # → 全生态 (fcitx/kitty/菜单) 随视频帧变色。视频放入
    # ${mainUser}/Pictures/Wallpapers/video/, Mod+W (binds.kdl) 唤出官方 picker 选视频。
    # 图片壁纸走 Noctalia 设置内的壁纸选择器 (automation 30min 轮换照常)。
    # ============================================================
    [plugins]
    enabled = ["noctalia/mpvpaper"]

    [plugin_settings."noctalia/mpvpaper"]
    video_directory = "/home/${mainUser}/Pictures/Wallpapers/video"
    mute = true
    # false: 停止视频/切静态时插件不回填末帧 —— 开着会让"动态切静态"播两次
    # 过渡动画 (第一次末帧回填, 第二次所选图, 用户可见)。关闭后 clear-all 直接
    # 恢复主壁纸层, 显示的即所选图。代价: ① 停止后不再有"末帧取色", 配色跟随
    # 静态图 (更符合预期); ② picker 的 Stop 不再触发 wallpaper_changed (走
    # setWallpaperEnabled 而非 setWallpaper), 轮播不会立即恢复 —— 下次手动
    # 切图或重启 shell 时恢复 (config.toml 的 enabled=true)。
    # 起播垫底缩略图走独立缓存 (~/.cache/noctalia/mpvpaper/<路径转写>.jpg,
    # 已存在则不受本开关影响, 无黑屏; 新增视频首次播放时无垫底)。
    extract_last_frame = false

    # GTK 明暗跟随 + 动态壁纸切静态桥接
    [hooks]
    theme_mode_changed = ["theme-sync"]   # 注意: home-manager 包在 /etc/profiles, 非 ~/.nix-profile
    wallpaper_changed = ["wallpaper-video-guard"]   # 播放中切静态壁纸 → 停视频并应用所选图
  '';
}
