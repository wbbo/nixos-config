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
    ./programs/scratchpad.nix
    ./programs/pigma.nix
    ./persist.nix
  ];

  home = {
    username = mainUser;
    homeDirectory = "/home/${mainUser}";
    stateVersion = "26.05";
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

    # Noctalia Shell(面板/通知/启动器/锁屏)
    noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
