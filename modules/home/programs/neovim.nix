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

      " ── 全局复制/粘贴 (Windows 习惯) ──
      " Ctrl+Insert 复制选中到系统剪贴板 (kitty 已放行该键给终端内程序)
      vnoremap <C-Insert> "+y     " visual: 复制选中
      nnoremap <C-Insert> "+yy    " normal: 复制当前行
      inoremap <C-Insert> <C-r>+  " insert: 粘贴剪贴板
      " Shift+Insert 粘贴由终端 (kitty) 层处理, neovim 无需配置

      " 系统剪贴板 provider (wl-clipboard) —— 让 + / * register 走 wl-copy/wl-paste
      lua << EOF
      vim.g.clipboard = {
        name = 'wl-clipboard',
        copy = { ['+'] = 'wl-copy', ['*'] = 'wl-copy' },
        paste = { ['+'] = 'wl-paste', ['*'] = 'wl-paste' },
      }
      EOF
    '';

    plugins = with pkgs.vimPlugins; [
      vim-nix # Nix 语法高亮 / 缩进
    ];
  };
}
