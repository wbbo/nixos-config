# Home Manager 入口 —— 主用户的家目录配置
# 由 hosts/default/configuration.nix 的 home-manager.users.<mainUser> 引入,
# mainUser 通过 extraSpecialArgs 传入 (见 hosts/default/configuration.nix)。
{ pkgs, noctalia, mainUser, ... }:
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
    ./programs/satty.nix
    ./programs/scratchpad.nix
    ./programs/pigma.nix
    ./programs/lutris.nix
    ./programs/nautilus.nix
    ./programs/wework-fix.nix
    ./fonts.nix
    ./persist.nix
  ];

  home = {
    username = mainUser;
    homeDirectory = "/home/${mainUser}";
    stateVersion = "26.05";
  };

  # 用户会话语言与 niri 的 environment{} 块 (modules/home/niri/config.kdl) 对齐。
  # 必须用 systemd.user.sessionVariables 而非 home.sessionVariables ——
  # 后者只进 shell source 的 hm-session-vars.sh, 而 ~/.config/environment.d/
  # 10-home-manager.conf (systemd user manager 的环境来源, 亦即 D-Bus 激活
  # 程序的继承源) 由前者生成 (nix eval 实测确认)。
  # 场景: niri 只给自己 spawn 的子进程注入 LANG=zh_CN.UTF-8, 经 D-Bus 激活
  # 拉起的程序 (如从 Firefox 点"打开所在文件夹"唤起 Nautilus) 走的是 systemd
  # user manager —— 那里默认 en_US.UTF-8 且无 LC_MESSAGES, gettext 解析不到
  # 中文 (实测表现: nautilus-open-any-terminal 右键菜单回退英文)。补上此项使
  # 两条启动路径语言一致; 需重新登录 (systemd user manager 启动时读取) 生效。
  systemd.user.sessionVariables.LANG = "zh_CN.UTF-8";

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
    noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default

    # 录屏工具 OBS Studio 走 Flathub Flatpak 安装, 与微信同一套路:
    # 系统级 /var/lib/flatpak 跨 rebuild 天然保留, 而 ~/.var/app/<app>
    # 属家目录, 在 modules/home/persist.nix 里显式持久化。
    # gpu-screen-recorder (GSR) 曾以 nixpkgs CLI 与 Flatpak 两种形态试用,
    # 2026-09-14 已全部移除 (nix 包下线 + Flatpak 卸载并清理运行时残留);
    # 日常录屏用 niri 的 record-toggle (wf-recorder, Mod+Alt+R)。
  ];
}
