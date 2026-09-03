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
  home.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    SDL_IM_MODULE = "fcitx";
    GLFW_IM_MODULE = "ibus"; # fcitx5 兼容 ibus
    QT_QPA_PLATFORM = "wayland;xcb";
    INPUT_METHOD = "fcitx";
  };

  # 雾凇拼音 Rime 配置
  # - __include 加载雾凇默认方案(词库/双拼/schema/标点/Lua 脚本)
  # - 默认 schema 为 rime_ice (雾凇拼音全拼)
  # - switcher 呼出热键: Ctrl+` 与 VSCode 终端面板冲突, 改用 Ctrl+Alt+Shift+F4
  xdg.dataFile."fcitx5/rime/default.custom.yaml".text = builtins.toJSON {
    patch = {
      __include = "rime_ice_suggestion:/";
      schema_list = [{
        schema = "rime_ice";
      }];
      menu.page_size = 9;
      switcher.hotkeys = [ "Control+Alt+Shift+F4" ];
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
  xdg.configFile."autostart/org.fcitx.Fcitx5.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Name=Fcitx 5
      GenericName=Input Method
      Comment=Start Input Method
      Exec=${fcitx5Pkgs}/bin/fcitx5 --disable notificationitem
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
