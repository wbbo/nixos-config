# 系统级程序与软件包
{ pkgs, ... }:
{
  ### 基础程序(系统级安装;/etc/shells、vendor 补全由此注册)
  # git / neovim / kitty / firefox 等用户程序由 Home Manager 统一管理(见 modules/home)
  programs = {
    bash.enable = true;
    fish.enable = true;
  };

  ### 系统软件包(参考 nixos-niri-noctalia)
  environment.systemPackages = with pkgs; [
    ### 兼容层 / Windows 程序
    wineWow64Packages.waylandFull
    winetricks

    ### 浏览器
    google-chrome

    ### 系统工具
    pciutils
    usbutils
    curl
    wget
    cachix
    btrfs-progs
    snapper
    git

    ### 多媒体
    ffmpeg-full
    libva-utils

    ### Wayland 工具链
    wl-clipboard
    grim
    slurp

    ### 终端 / 编辑器(参考 nixos-niri-noctalia)
    kitty
    alacritty
    helix

    ### 美化 / 状态
    starship
    bibata-cursors

    ### 文件管理
    nautilus
    yazi

    ### 系统监视
    cmatrix

    ### 启动器
    fuzzel

    ### 无线 / 网络诊断
    iw                         # Wi-Fi 接口/链路质量/扫描
    networkmanagerapplet       # Wi-Fi 系统托盘(兼容各桌面环境)

    ### 基础网络调试
    dnsutils                   # dig / nslookup
    iputils                    # ping / traceroute
  ];
}
