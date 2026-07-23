# fish shell 用户配置
# 二进制由系统级 programs.fish.enable 提供(/etc/shells、vendor 补全),
# 此处只管理 ~/.config/fish/config.fish,避免重复安装。
{ ... }:
{
  xdg.configFile."fish/config.fish".text = ''
    # 取消欢迎语
    set -g fish_greeting

    # 默认编辑器
    set -gx EDITOR nvim
    set -gx VISUAL nvim

    # 别名(依赖 bat / eza / nvim,由 Home Manager 安装到用户环境)
    alias cat 'bat --paging=never'
    alias ls 'eza --icons'
    alias ll 'eza -la --git --icons'
    alias lt 'eza --tree --icons --level=2'
    alias vim 'nvim'
    alias :q 'exit'
    alias cls 'clear'
  '';
}
