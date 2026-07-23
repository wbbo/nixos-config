# Home Manager 入口 —— 用户 wbb 的家目录配置
# 由 hosts/wbb/configuration.nix 的 home-manager.users.wbb 引入。
{ pkgs, noctalia, ... }:
{
  imports = [
    ./niri
    ./programs/kitty.nix
    ./programs/fish.nix
    ./programs/fuzzel.nix
    ./programs/git.nix
    ./programs/firefox.nix
    ./programs/fcitx5.nix
    ./programs/noctalia.nix
    ./programs/neovim.nix
  ];

  home = {
    username = "wbb";
    homeDirectory = "/home/wbb";
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
    fastfetch     # 系统信息(替代 neofetch)
    unzip
    gzip
    playerctl     # 媒体键控制
    brightnessctl # 亮度(笔记本)
    pavucontrol   # 音量图形控制

    # Noctalia Shell(面板/通知/启动器/锁屏)
    noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
