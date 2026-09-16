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

  # 用户会话语言统一由 modules/nixos/greetd.nix 的 greetd 单元 Environment
  # 注入 (经 niri-session 的 `systemctl --user import-environment` 进入
  # systemd user manager = D-Bus 激活程序的继承源)。
  #
  # 此处**不要**再写 `systemd.user.sessionVariables.LANG`: 它生成的
  # ~/.config/environment.d/10-home-manager.conf 至多只在 user manager
  # 启动那一刻生效, 而登录时 niri-session 那句 import-environment 会用
  # 会话的值 (en_US, 来自 PID1/locale.conf) 整体覆盖它 —— 2026-09-12 曾以
  # 此为修复, 09-16 实测证伪 (Nautilus 经 D-Bus 激活仍是英文), 已移除。

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
