# fcitx5 中文输入法 —— Home Manager 用户配置
# 系统配置见 modules/nixos/ime.nix
{ config, pkgs, lib, ... }: let
  # 注入雾凇拼音 (rime-ice) 词库，替代 fcitx5-chinese-addons
  # rimeDataPkgs 按顺序合并: rime-ice 在后可覆盖 rime-data 同名文件
  fcitx5Rime = pkgs.fcitx5-rime.override {
    rimeDataPkgs = [ pkgs.rime-data pkgs.rime-ice ];
  };
  fcitx5Pkgs = pkgs.qt6Packages.fcitx5-with-addons.override {
    addons = [
      fcitx5Rime                    # Rime 引擎 + 雾凇拼音词库
      pkgs.qt6Packages.fcitx5-qt    # fcitx5 Qt immodule
    ];
  };
in
{
  # fcitx5 包放入系统包(由 Home Manager 管理)
  home.packages = [ fcitx5Pkgs ];

  # 环境变量(所有 Wayland 应用生效, Niri 环境变量在 niri config.kdl 也有)
  # 方案 3 (2026-09-12, 方案 1 验证通过后): GTK/SDL 的 legacy IM module
  # 变量全部不设 —— Wayland 下应走原生 text-input 协议 (官方 Wiki:
  # "Do NOT set GTK_IM_MODULE" / KDE 段 "Do not set GTK_IM_MODULE &
  # QT_IM_MODULE & SDL_IM_MODULE")。
  #   - XMODIFIERS 必须保留: XWayland 应用 (wine 企业微信) 走 XIM。
  #   - QT_IM_MODULES="wayland;fcitx": Qt 6.8.2+ 官方写法 (本机 Qt 6.11.1),
  #     优先 Wayland 原生、fcitx 回退; 不再设旧的 QT_IM_MODULE —— 若将来
  #     引入 Qt5 应用需把它加回。
  #   - GLFW_IM_MODULE / INPUT_METHOD 官方未提及, 保留 (价值存疑但无害)。
  home.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
    QT_IM_MODULES = "wayland;fcitx";
    GLFW_IM_MODULE = "ibus"; # fcitx5 兼容 ibus
    QT_QPA_PLATFORM = "wayland;xcb";
    INPUT_METHOD = "fcitx";
  };

  # 雾凇拼音 Rime 配置
  # - __include 加载雾凇默认方案(词库/双拼/schema/标点/Lua 脚本)
  # - 默认 schema 为 rime_ice (雾凇拼音全拼)
  # - switcher 呼出热键: Ctrl+` 与 VSCode 终端面板冲突, 改用 Ctrl+Alt+Shift+F4
  # - 候选翻页键: 雾凇默认的 - / = 保留, 另追加 , / . (两套并存)。
  #   用 @after 索引插入而非直接写 bindings: rime 对 key_binder/bindings 这类
  #   按键表是整体替换式 patch (实测 librime 1.16.1: 连 "/+" 追加语法也是整体
  #   覆盖), 直接赋值会顶掉雾凇其余键位 (Tab/Alt 移动拼音光标、Ctrl+Shift+3/4
  #   切换标点/简繁、小键盘映射)。@after 5 / @after 6 把两条插在键位表第 5、6
  #   条 (minus/equal) 之后; 值必须是单个对象 (数组会被当成一个元素嵌套进去)。
  #   升级 rime-ice 后若键位表顺序变化, 索引需复核。
  xdg.dataFile."fcitx5/rime/default.custom.yaml".text = builtins.toJSON {
    patch = {
      __include = "rime_ice_suggestion:/";
      schema_list = [{
        schema = "rime_ice";
      }];
      menu.page_size = 9;
      switcher.hotkeys = [ "Control+Alt+Shift+F4" ];
      # has_menu: 候选菜单展开时始终翻页, 不输出标点 (雾凇注释里的写法)
      "key_binder/bindings/@after 5" = {
        when = "has_menu";
        accept = "comma";
        send = "Page_Up";
      };
      "key_binder/bindings/@after 6" = {
        when = "has_menu";
        accept = "period";
        send = "Page_Down";
      };
    };
  };

  # rime_ice 雾凇拼音: 默认简体 + 始终英文半角标点 + 回车上屏拼音
  # switches 整体重写会覆盖雾凇原列表, 故保留全部原开关再改 reset
  xdg.dataFile."fcitx5/rime/rime_ice.custom.yaml".text = ''
    patch:
      switches:
        - name: ascii_mode
          states: [ 中, Ａ ]
          reset: 1  # 每个输入会话默认英文, 按 Shift 切中文 (无 reset 时 fcitx5 进程内记忆上次中英状态)
        - name: ascii_punct
          states: [ ¥, $ ]
          reset: 1  # 默认英文标点: 中文输入时 , . " 等直接上屏半角
        - name: traditionalization
          states: [ 简, 繁 ]
          reset: 0  # 默认简体 (0 = 简)
        - name: emoji
          states: [ 💀, 😄 ]
          reset: 1
        - name: full_shape
          states: [ 半角, 全角 ]
          reset: 0  # 始终半角 (Shift+Space 临时切换, 会话重置回半角)
        - name: search_single_char
          states: [正常, 单字]
          abbrev: [词, 单]
      # 回车 = 上屏拼音编码, 不切换输入法 (rime 默认 commit_code, 无绑定即生效)
      # 注意与 Shift_L: commit_code 的区别: 回车只提交原始拼音, 不改 ascii_mode;
      # Shift 会顺带切到英文。若需回车确认候选, 在此追加 {accept: Return, send: space, when: has_menu}
  '';

  # rime 重新部署闭环 —— xdg.dataFile 是指向 store 的 symlink, mtime 恒为
  # 1970-01-01, 而 librime 靠 custom.yaml mtime 对比 last_deploy_time 判断
  # 是否重新部署 → 永远判定"无变化", 修改配置后 rime 一直跑旧 build/。
  # 此处以 symlink target (随内容变化的 store 路径) 作指纹: 变化时清空
  # build/ 强制下次 fcitx5 启动全量重建, 并记 stamp 防重复清理。
  # (switch 后仍需 fcitx5 -rd 让新配置加载)
  home.activation.fcitx5RimeRedeploy = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    rime_dir="$HOME/.local/share/fcitx5/rime"
    stamp="$HOME/.local/state/fcitx5-rime-deployed"
    # 注意: 激活脚本是平铺的 set -eu, 这里绝不能 exit —— 会中断后续钩子
    # (installNvm 等), 新装机无 rime 目录时整个激活都会静默截断
    if [ -d "$rime_dir" ]; then
      fp="$(readlink "$rime_dir/default.custom.yaml" 2>/dev/null)$(readlink "$rime_dir/rime_ice.custom.yaml" 2>/dev/null)"
      if [ -n "$fp" ] && [ "$(cat "$stamp" 2>/dev/null)" != "$fp" ]; then
        rm -rf "$rime_dir/build"
        # 主动编译而非依赖 fcitx5 启动维护: fcitx5-rime 的 maintenance 只对比
        # 部署记录, 清空 build/ 后它不会自动全量重建 (实测踩坑: build 空且无方案)
        # 共享数据目录 = rimeDataPkgs 合并结果 (rime-data + rime-ice)
        if ${pkgs.librime}/bin/rime_deployer --build "$rime_dir" "${fcitx5Rime}/share/rime-data" >/dev/null 2>&1; then
          echo "==> rime 重新部署完成 (build/ 已重建)"
        else
          echo "警告: rime_deployer 失败, fcitx5 首启时会尝试自行部署"
        fi
        mkdir -p "$HOME/.local/state"  # set -e 下重定向失败会终止激活脚本, 先确保目录存在
        printf '%s' "$fp" > "$stamp"
      fi
    fi
  '';

  # fcitx5 只保留 rime 单输入法 —— 中英切换完全由 rime 的 ascii_mode (Shift) 承担,
  # 移除 keyboard-us 避免两层切换 (fcitx5 层切 IM / rime 层切 ascii_mode) 状态混乱;
  # Ctrl+Space 从此无切换目标, 英文输入用 rime 的 ascii_mode (Shift 切换)
  # 没有此文件则首次使用需手动在 fcitx5 config GUI 里添加 Rime
  # force = true: 允许覆盖 fcitx5 GUI 手动生成的 profile (避免 collide)
  xdg.configFile."fcitx5/profile" = {
    force = true;
    text = ''
      [Groups/0]
      Name=Default
      Default Layout=us
      DefaultIM=rime

      [Groups/0/Items/0]
      Name=rime
      Layout=

      [GroupOrder]
      0=Default
    '';
  };

  # fcitx5 全局热键: 清空默认 AltTriggerKeys=Shift_L (左 Shift 切中英)
  # 该默认热键会在框架层拦截 Shift 并上屏候选汉字, 导致 rime 的
  # Shift_L: commit_code (上屏拼音编码并切英文) 收不到按键、形同虚设;
  # 清空后 Shift 透传给 rime 生效。中英切换交给 rime 的 ascii_mode。
  xdg.configFile."fcitx5/config" = {
    force = true;
    text = ''
      [Hotkey]
      AltTriggerKeys=
    '';
  };

  # 隐藏托盘输入法图标 —— 单 rime 后托盘中/英图标已无信息量。
  # 实测: addon conf 的 Enabled=False 对 OnDemand 的 notificationitem 不生效
  # (fcitx5 5.1.19 忽略配置层禁用, 日志显示仅 --disable 命令行参数有效)。
  # fcitx5 由 systemd autostart 启动 (Exec 无参数), 此处覆盖
  # ~/.config/autostart/org.fcitx.Fcitx5.desktop (优先级高于 /etc/profiles
  # 的同名文件), 在 Exec 注入 --disable notificationitem 禁用托盘。
  # 候选框左侧的中/英标识不受影响; 重新部署用 fcitx5 -rd。
  #
  # XIM 就绪等待: niri 25.08+ 的 X11 socket 由按需 spawn 的 xwayland-satellite
  # 承载, fcitx5 启动早于首个 X client 时, 其 XIM 前端注册会静默失败
  # (root 上无 _XIM_SERVERS → wine 等 XIM 客户端无法输入中文)。
  # fcitx5 本体改由 systemd 用户服务常驻 (Restart 自动拉起, 替代 autostart;
  # 中途死亡无人监管曾导致全系统无法输入中文), ExecStartPre: 等待 X socket
  # → 触发 satellite 拉起 → 杀掉残留实例 (单实例锁会拒新实例造成重启循环)。
  # 用户级 autostart desktop 保留但改为空操作, 覆盖 fcitx5 包自带的系统级
  # autostart (否则登录时无等待的实例抢跑占坑)。
  # XIM 健康守护: niri 的 X server (xwayland-satellite 承载) 重启后 (显示器断连/
  # 手动操作/配置重载), fcitx5 的 X 连接断掉且**不会自动重连** —— 进程存活但
  # root 上 _XIM_SERVERS 消失, 所有 XIM 客户端 (wine 等) 静默无法输入中文。
  # 本守护每 5 秒检查: X socket 存在 + fcitx5 在跑 + _XIM_SERVERS 缺失 → 重启
  # fcitx5.service 重新注册 (触发后冷却 30 秒)。注意 writeShellScript 不注入
  # runtimeInputs 的 PATH, 脚本内命令必须绝对路径。
  systemd.user.services.fcitx5-xim-guard = {
    Unit = {
      Description = "Restart fcitx5 when its XIM registration is lost (X server restart)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "fcitx5-xim-guard" ''
        delay=30
        while true; do
          # X 可用性判据 = xprop 成功执行。不能用 socket 存在判断 (socket 由
          # niri 持有 listenfd 传给 satellite, satellite 死后 socket 仍在)。
          # 属性名为 XIM_SERVERS (无下划线, xprop 实测)。
          # XIM 丢失 → restart (指数退避, 上限 300s, 防永久失败时无限重启输入法);
          # fcitx5 未跑 (退出 0 静默 / 手动 stop) → start。
          out=$(${pkgs.coreutils}/bin/timeout 3 env DISPLAY=:0 ${pkgs.xorg.xprop}/bin/xprop -root 2>/dev/null) || out=""
          if [ -n "$out" ]; then
            if ! systemctl --user is-active --quiet fcitx5.service; then
              systemctl --user start fcitx5.service
            elif [[ "$out" != *XIM_SERVERS* ]]; then
              echo "XIM registration lost, restarting fcitx5 (next cooldown ''${delay}s)"
              systemctl --user restart fcitx5.service
              sleep "$delay"
              delay=$((delay * 2))
              [ "$delay" -gt 300 ] && delay=300
              continue
            else
              delay=30  # XIM 正常: 重置退避
            fi
          fi
          sleep 5
        done
      '';
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.fcitx5 = {
    Unit = {
      Description = "Fcitx5 input method";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # systemd 用户环境缺显示相关变量, fcitx5 连不上 Wayland/X 会静默退出。
      # 不设 GTK_IM_MODULE/QT_IM_MODULE: Wayland 下 GTK/Qt 走原生 text-input
      # (官方 Wiki 要求), 且 fcitx5 检测到自身进程环境存在这两个变量会弹
      # "Wayland Diagnose" 提示框 (检测的是 fcitx5 自己的环境, 不是客户端的;
      # 字符串实证在 fcitx5-with-addons 的 .so 中) —— 上次清理只改了会话
      # 变量与 HM environment.variables, 漏了这里, 故提示仍在。
      # XMODIFIERS 必须保留: XWayland/wine 企业微信走 XIM。
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "DISPLAY=:0"
        "XMODIFIERS=@im=fcitx"
      ];
      ExecStartPre = pkgs.writeShellScript "fcitx5-wait-x" ''
        # 清理 unit 之外的野实例 (手动启动/历史漂留), 避免单实例锁冲突:
        # nix wrapper 进程 comm 是 `.fcitx5-wrapped`, pgrep/pkill -x fcitx5
        # 永不匹配 (曾致清理失效)。僵死的 fcitx5 忽略 SIGTERM, 先 TERM 后 KILL。
        ${pkgs.procps}/bin/pkill -x '[.]fcitx5-wrapped' 2>/dev/null || true
        sleep 1
        ${pkgs.procps}/bin/pkill -9 -x '[.]fcitx5-wrapped' 2>/dev/null || true
        for i in $(seq 1 30); do
          [ -S /tmp/.X11-unix/X0 ] && break
          sleep 1
        done
        ${pkgs.xorg.xprop}/bin/xprop -root >/dev/null 2>&1 || true
        sleep 2
      '';
      ExecStart = "${fcitx5Pkgs}/bin/fcitx5 --disable notificationitem";
      # always: fcitx5 遇单实例锁冲突会以退出码 0 静默退出 (on-failure 不重试),
      # ExecStartPre 清理野实例后该场景消失, always 兜底其余静默退出情形
      Restart = "always";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # 覆盖 dbus activation: 名字空缺瞬间 dbus-daemon 会按包自带的 service 文件
  # 拉起竞争实例, 抢占 org.fcitx.Fcitx5 导致 systemd 实例启动失败 (退出码 0
  # 的静默竞争)。用户级同名文件优先, Exec 指向 true 使 activation 变为空操作
  # (必须用 coreutils 的绝对路径: NixOS 无 /bin/true, 否则 activation 报 exec 错误)
  xdg.dataFile."dbus-1/services/org.fcitx.Fcitx5.service".text = ''
    [D-BUS Service]
    Name=org.fcitx.Fcitx5
    Exec=${pkgs.coreutils}/bin/true
  '';

  xdg.configFile."autostart/org.fcitx.Fcitx5.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Name=Fcitx 5
      GenericName=Input Method
      Comment=Disabled: managed by systemd user service fcitx5
      Exec=true
      Icon=fcitx
      Terminal=false
      Type=Application
      Categories=System;Utility;
      StartupNotify=false
      X-GNOME-Autostart-enabled=true
    '';
  };

  # ── NyxMellow 动态 fcitx5 皮肤 (Noctalia 模板渲染) ──────────────────────
  # 模板源部署到 ~/.local/share/fcitx5/themes/nyxmellow/templates/, 由 Noctalia
  # [theme.templates.user.nyxmellow_*] 渲染为 theme.conf/panel.svg/highlight.svg
  # (见 noctalia.nix)。占位符已规范化为 {{colors.x.default.hex}} 无空格格式。
  xdg.dataFile."fcitx5/themes/nyxmellow/templates/theme.conf".source = ./fcitx5/nyxmellow/templates/theme.conf;
  xdg.dataFile."fcitx5/themes/nyxmellow/templates/panel.svg".source = ./fcitx5/nyxmellow/templates/panel.svg;
  xdg.dataFile."fcitx5/themes/nyxmellow/templates/highlight.svg".source = ./fcitx5/nyxmellow/templates/highlight.svg;

  # fcitx5 UI 使用 NyxMellow 主题 (force 覆盖 GUI 生成)
  # Font: 候选栏字体统一 Maple Mono NF CN (默认为 Sans → Noto Sans CJK SC)
  xdg.configFile."fcitx5/conf/classicui.conf" = {
    force = true;
    text = ''
      Font="Maple Mono NF CN 12"
      Theme=nyxmellow
      DarkTheme=nyxmellow
      UseDarkTheme=False
    '';
  };
}
