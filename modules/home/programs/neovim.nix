# 编辑器 Neovim(用户配置层)
{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;

    extraConfig = ''
      set number
      set relativenumber
      set tabstop=4
      set shiftwidth=4
      set expandtab
      set autoindent
      set smartindent
      set termguicolors
      set mouse=a
      set scrolloff=4
      set ignorecase
      set smartcase
      syntax on
    '';

    plugins = with pkgs.vimPlugins; [
      vim-nix # Nix 语法高亮 / 缩进
    ];
  };
}
