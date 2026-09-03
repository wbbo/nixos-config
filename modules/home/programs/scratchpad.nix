# Scratchpad 持久浮动终端 —— NyxNiri 脚本移植, NixOS 声明式打包
#
# NixOS 哲学落地点:
# - 脚本入 repo (modules/home/programs/scratchpad/), 由 nix 打包为 store 产物,
#   依赖 (jq/kitty/tmux/niri) 由 nix 提供, 不依赖系统散装安装。
# - niri 绑定 Mod+Grave 拉起 (见 binds.kdl)。
{ pkgs, ... }:
let
  # Scratchpad 生命周期控制器 (kitty 持久浮动终端 + tmux 保活会话, 跨工作区搬运)
  toggle = pkgs.writeShellApplication {
    name = "niri-scratch-toggle";
    runtimeInputs = [ pkgs.jq pkgs.kitty pkgs.tmux pkgs.niri pkgs.fish pkgs.coreutils ];
    text = builtins.readFile ./scratchpad/toggle.sh;
  };
in {
  home.packages = [ toggle ];
}
