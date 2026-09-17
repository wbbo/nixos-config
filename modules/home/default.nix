# Home Manager 入口 —— 主用户的家目录配置
# 由 hosts/default/configuration.nix 的 home-manager.users.<mainUser> 引入,
# mainUser 通过 extraSpecialArgs 传入 (见 hosts/default/configuration.nix)。
{ pkgs, noctaliaPkg, mainUser, ... }:
{
  imports = [
    ./niri
    ./programs/kitty.nix
    ./programs/fish.nix
    ./programs/fuzzel.nix
    ./programs/git.nix
    ./programs/ssh.nix
    ./programs/firefox.nix
    ./programs/thunderbird.nix
    ./programs/fcitx5.nix
    ./programs/noctalia.nix
    # noctaliaPkg (带本地补丁的 noctalia 包) 的定义, 供上面 noctalia.nix 与本文件共用
    ./programs/noctalia-package.nix
    ./programs/neovim.nix
    ./programs/vscode.nix
    ./programs/cc-switch.nix
    ./programs/claude.nix
    ./programs/codex.nix
    ./programs/udiskie.nix
    ./programs/java.nix
    ./programs/go.nix
    ./programs/rust.nix
    ./programs/python.nix
    ./programs/node.nix
    ./programs/c-cpp.nix
    ./programs/starship.nix
    ./programs/scratchpad.nix
    ./programs/pigma.nix
    ./programs/lutris.nix
    ./programs/hmcl.nix
    ./programs/nautilus.nix
    # Typora 是 Flatpak 装的 (不在 Nix 里), 本模块只做它那份进阶配置的声明化
    ./programs/typora.nix
    ./programs/wework-fix.nix
    ./fonts.nix
    ./persist.nix
  ];

  home = {
    username = mainUser;
    homeDirectory = "/home/${mainUser}";
    stateVersion = "26.05";
  };

  # ── 用户会话语言 (D-Bus 激活路径) ──────────────────────────────────
  # 必须**在 import-environment 之后**再设一次, 否则会被它覆盖。
  #
  # 完整链路 (2026-09-16 逐段实测, 含读 /proc/<pid>/environ 取证):
  #   D-Bus 激活的 GUI 程序继承 systemd --user 的环境 —— 实测从 Obsidian 唤起
  #   Nautilus 时, 其 /proc/<pid>/cgroup 落在
  #   app-dbus-:1.2-org.gnome.Nautilus.slice, 父进程 = systemd --user,
  #   environ 里 LANG=en_US.UTF-8 → 界面英文。与 Obsidian/Flatpak 均无关。
  #
  #   user manager 的 LANG 来源: niri-session 的 `systemctl --user
  #   import-environment`(无参数 = 导入整个登录会话环境)。会话环境由 PAM 构造,
  #   /etc/pam/environment 里是 `LANG DEFAULT="en_US.UTF-8"` (源自
  #   i18n.defaultLocale), 于是 user manager 被覆盖成 en_US。
  #
  # 两条看似可行、实测无效的路径 (勿重蹈):
  #   - `systemd.user.sessionVariables.LANG` → environment.d: 只在 user manager
  #     **启动时**生效, 随后被上面那句 import-environment 覆盖, 等于没设。
  #     (另注: Linger=yes, user manager 开机即起, 更早于此。)
  #   - greetd 单元的 `Environment=LANG` (modules/nixos/greetd.nix): 只作用于
  #     greetd 自身进程, 经 PAM 建会话时被 pam_env 的 DEFAULT= 重新设上, 传不
  #     进会话 —— 回滚并重启后实测 user manager 仍是 en_US。
  #
  # 可行解: oneshot 用户服务挂在 graphical-session.target 之后 —— 此时
  # niri.service 已由 niri-session 启动, import-environment 早已跑完, 再
  # set-environment 就不会被覆盖。实测手工执行同一条命令后, 从 Obsidian 唤起的
  # Nautilus 立即变为中文。
  #
  # 端到端实测 (2026-09-17 journal 取证, 非推断):
  #   9-16 19:24:43  user manager 启动 (开机)
  #   9-16 19:25:00  session-lang **自动运行** ← 会话启动后 17 秒
  #                  → 证明 WantedBy=graphical-session.target 的自动触发成立
  #   验证: systemctl --user show-environment | grep LANG → zh_CN.UTF-8 ✓
  # 注意运行后服务处于 inactive(dead) 是**预期**状态, 不是故障 —— 见下方
  # 不加 RemainAfterExit 的理由 (正因如此, 每次会话启动都能重跑)。
  #
  # 已知局限: 只对**此后**新激活的程序生效; graphical-session.target 到达之前
  # 启动的 D-Bus 服务仍是 en_US。日常使用(登录后开应用)无影响 —— niri 自己
  # spawn 的子进程另有 niri config.kdl 的 environment{} 块兜底。
  systemd.user.services.session-lang = {
    Unit = {
      Description = "将会话 LANG 固定为中文 (niri-session 的 import-environment 会覆盖 environment.d)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user set-environment LANG=zh_CN.UTF-8";
      # 刻意**不加** RemainAfterExit: 加上后服务首次成功即长期处于 active(exited),
      # systemd 对已 active 的 oneshot 执行 `start` 是**静默空操作**, 不会重跑
      # ExecStart —— 跨会话(登出再登录)时就会失效。去掉后每次拉起都会真正执行。
      # 排查提示: 验证该服务必须用 `systemctl --user restart`, 用 `start` 会因
      # 上述原因看似"服务成功但没生效", 极易误判为逻辑错误 (本轮已踩)。
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # XDG 用户目录: 统一声明为英文路径 (HM 默认值即 $HOME/Downloads 等英文名)。
  # 此前系统完全没有 ~/.config/user-dirs.dirs —— HM 的 xdg.userDirs 默认
  # 不启用, 于是各应用只能自己猜"下载目录在哪": 硬编码的用 ~/Downloads,
  # 按 locale 推导的 ($LANG=zh_CN.UTF-8) 造出 ~/下载, 两套并存。
  # createDirectories = false: 只写声明文件供所有应用读取, 不额外创建
  # Desktop/Public/Templates 这些用不到的目录 (已存在的
  # Downloads/Documents/Pictures/Videos 保持原样)。
  xdg.userDirs = {
    enable = true;
    createDirectories = false;
  };

  # 让 Home Manager 自身可管理(避免首次激活告警)
  programs.home-manager.enable = true;

  ### 用户级软件包(CLI 增强 / 桌面小工具)
  home.packages = with pkgs; [
    bat           # cat 替代,带语法高亮
    eza           # ls 替代,带图标
    fd            # find 替代
    ripgrep       # grep 替代
    btop          # 系统监视器
    htop          # 系统监视器 (替代 top, 无粗体中文表头发虚问题)
    fastfetch     # 系统信息(替代 neofetch)
    unzip
    gzip
    playerctl     # 媒体键控制
    brightnessctl # 亮度(笔记本)
    pavucontrol   # 音量图形控制

    # GTK 明暗主题 (theme-sync 切换 adw-gtk3 / adw-gtk3-dark, 需先安装)
    adw-gtk3

    # Adwaita 图标主题: GTK 默认 icon-theme 的查找目标。不装则图标解析回退到
    # hicolor (仅 41 个图标), 较新图标缺失 —— 实测 Nautilus 侧边栏"收藏"的
    # starred-symbolic 在全部 12 个 XDG_DATA_DIRS 路径中均找不到, 显示为破图
    # 占位符。装上后 Adwaita 进用户 profile 的 share/icons, 图标恢复正常。
    adwaita-icon-theme

    # Noctalia Shell(面板/通知/启动器/锁屏)
    noctaliaPkg

    # 录屏工具 OBS Studio 走 Flathub Flatpak 安装, 与微信同一套路:
    # 系统级 /var/lib/flatpak 跨 rebuild 天然保留, 而 ~/.var/app/<app>
    # 属家目录, 在 modules/home/persist.nix 里显式持久化。
    # gpu-screen-recorder (GSR) 曾以 nixpkgs CLI 与 Flatpak 两种形态试用,
    # 2026-09-14 已全部移除 (nix 包下线 + Flatpak 卸载并清理运行时残留);
    # 日常录屏用 niri 的 record-toggle (wf-recorder, Mod+Alt+R)。
  ];
}
