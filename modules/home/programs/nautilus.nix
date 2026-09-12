# Nautilus 文件管理器增强
{ pkgs, ... }:
{
  # "在终端中打开"右键菜单 —— Nautilus 无内置该功能 (GNOME 生态历来靠扩展),
  # 用社区扩展 nautilus-open-any-terminal: python 扩展, 由 nautilus-python
  # 加载 (扫描 $XDG_DATA_DIRS/nautilus-python/extensions/, 装包即被识别)。
  # 终端选择走 dconf —— 扩展读 gsettings
  # com.github.stunkymonkey.nautilus-open-any-terminal 的 terminal 键。
  # 注: kitty.nix 里的 xdg-terminal-exec 是另一套规范, Nautilus 不使用;
  # 保留无妨 (其它遵循该规范的工具可用), 但不能替代本扩展。
  home.packages = with pkgs; [
    nautilus-python
    nautilus-open-any-terminal
  ];

  dconf.settings."com/github/stunkymonkey/nautilus-open-any-terminal" = {
    terminal = "kitty";
  };
}
