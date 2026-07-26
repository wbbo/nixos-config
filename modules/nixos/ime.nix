# fcitx5 中文输入法 —— 系统级 i18n 支持
# Home Manager 用户配置见 modules/home/programs/fcitx5.nix
{ config, lib, ... }:
{
  # Wayland 输入法协议(需要 fcitx5-with-addons 中的 fcitx5-wayland)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true; # 为 Niri/Wayland 提供 text-input-v1/v3 支持
  };
}
