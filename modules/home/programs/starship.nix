# Starship 提示符 —— 完全声明式管理
#
# Noctalia 的 starship 模板渲染已关闭 (见 noctalia.nix): 它与自定义 powerline
# palette 'colors' 冲突 (Noctalia 会把 palette 行改成 "noctalia", 导致 color_*
# 引用失效 → 无彩色)。因此 starship.toml 不再需要可写 + 保留 palette 区的逻辑,
# 改为每次 switch 用 repo 模板覆盖, 保证配色恒定。
{ pkgs, lib, ... }:
{
  home.activation.copyStarshipWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -m 0644 -- "${./starship.toml}" "$HOME/.config/starship.toml"
  '';
}
