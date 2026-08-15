# fish shell 用户配置
# 二进制由系统级 programs.fish.enable 提供(/etc/shells、vendor 补全),
# 此处只管理 ~/.config/fish/config.fish,避免重复安装。
{ pkgs, ... }:
let
  # top 专用 terminfo (topm): procps top 的表头反白写死 (Cap_reverse),
  # 深色终端下 = 白底深字 (kitty 中表头"发虚/白底"的根源)。
  # 把 rev/smso 从反白 \E[7m 改为加粗 \E[1m, 表头变深底浅字。
  # topm.terminfo 由 `infocmp -x kitty` 导出后改 rev/smso 得到。
  topm = pkgs.runCommand "topm-terminfo" { nativeBuildInputs = [ pkgs.ncurses ]; } ''
    tic -x -o $out ${./topm.terminfo}
  '';
in {
  # 链接自定义 terminfo 到 ~/.terminfo, top alias 用 TERM=topm 生效
  home.file.".terminfo/t/topm".source = "${topm}/t/topm";

  xdg.configFile."fish/config.fish".text = ''
    # 取消欢迎语
    set -g fish_greeting

    # 默认编辑器
    set -gx EDITOR nvim
    set -gx VISUAL nvim

    # ~/.local/bin: 原生安装脚本装的 CLI (claude / cc-switch 等)
    fish_add_path ~/.local/bin
    # rustup 的 cargo/rustc 经 rustup toolchain 装到 ~/.cargo/bin
    fish_add_path ~/.cargo/bin

    # Starship prompt
    starship init fish | source

    # 别名
    alias cat 'bat --paging=never'
    alias ls 'eza --icons'
    alias grep 'grep --color=auto'
    alias ll 'eza -la --git --icons'
    alias lt 'eza --tree --icons --level=2'
    alias vim 'nvim'
    alias :q 'exit'
    alias cls 'clear'
    # top: TERM=topm 关闭表头反白 (自定义 terminfo, rev 改为加粗) + 英文输出
    alias top 'TERM=topm LANG=C command top'
    alias claude 'claude --dangerously-skip-permissions'
    alias cs 'cc-switch'
  '';
}
