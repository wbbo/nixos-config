# 编辑器 Neovim —— LazyVim (lazy.nvim 运行时配置框架)
# starter 由 fetchFromGitHub 拉取, 部署到 ~/.config/nvim;
# 插件由 lazy.nvim 首次启动时自动安装 (LazyVim 官方方式, 非声明式)。
# init.lua (LazyVim) 优先于 home-manager 的 init.vim, 自定义 extraConfig 移除。
{ pkgs, ... }:
let
  lazyvimStarter = pkgs.fetchFromGitHub {
    owner = "LazyVim";
    repo = "starter";
    rev = "803bc181d7c0d6d5eeba9274d9be49b287294d99";
    sha256 = "sha256-QrpnlDD4r1X4C8PqBhQ+S3ar5C+qDrU1Jm/lPqyMIFM=";
  };
in {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
    # 不设 extraConfig/plugins —— LazyVim 完整接管 (init.lua 优先)
  };

  # LazyVim 运行依赖 (git 系统已有; lazygit/fd/rg 为 LazyVim 工具集成)
  home.packages = with pkgs; [ lazygit fd ripgrep ];

  # LazyVim starter 配置 (lazy.nvim 首次启动自动安装插件)
  xdg.configFile."nvim" = {
    source = lazyvimStarter;
    recursive = true;
  };
}
