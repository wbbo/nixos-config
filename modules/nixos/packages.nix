# 系统级程序与软件包
{ pkgs, ... }:
{
  ### 基础程序(系统级安装;/etc/shells、vendor 补全由此注册)
  # git / neovim / kitty / firefox 等用户程序由 Home Manager 统一管理(见 modules/home)
  # 注: programs.git.enable 只是把 git 包放系统环境 + 生成 /etc/gitconfig,
  # 不涉及用户配置 (~/.gitconfig 仍归 HM); 二者并存无冲突。
  programs = {
    bash.enable = true;
    fish.enable = true;
    # git-lfs: 装包 + /etc/gitconfig 自动写 filter.lfs (clean/smudge/process)。
    # 系统默认 git 不带 lfs, git lfs 子命令会报 "'lfs' 不是一个 git 命令"。
    # package 换 git.override: svnSupport 加 git svn 子命令 (公司仓库走
    # SVN); withLibsecret 加凭据助手 (HTTPS 凭据存 GNOME keyring);
    # withSsh 硬编码 ssh 路径 (systemd 单元环境不依赖 PATH)。
    # 与 HM programs.git.package 参数一致 → 同一 store 路径, 只有一份 git。
    git = {
      enable = true;      # gitconfig 生成的必需前提 (模块源码 mkIf cfg.enable)
      lfs.enable = true;
      package = pkgs.git.override {
        svnSupport = true;
        withLibsecret = true;
        withSsh = true;
      };
    };
  };

  ### 系统软件包(参考 nixos-niri-noctalia)
  environment.systemPackages = with pkgs; [
    ### 系统工具
    btrfs-assistant # Snapper/btrfs 图形管理 (Qt)
    pciutils
    usbutils
    curl
    jq
    yq
    wget
    cachix
    btrfs-progs

    ### 多媒体
    ffmpeg-full
    libva-utils

    ### Wayland 工具链
    wl-clipboard
    grim
    slurp

    ### 美化 / 状态
    starship
    bibata-cursors

    ### 文件管理
    nautilus
    yazi

    ### 终端装饰
    cmatrix

    ### 无线 / 网络诊断
    iw                         # Wi-Fi 接口/链路质量/扫描
    # networkmanagerapplet 已移除: 托盘网络图标由 noctalia network widget 提供
    # (左键 control-center 网络面板 / 右键开关无线), 避免外部图标与 noctalia 观感不一致

    ### 基础网络调试
    dnsutils                   # dig / nslookup
    iputils                    # ping / traceroute
  ];
}
