# Lutris —— 多平台游戏聚合启动器 (GOG / Epic / Battle.net / 模拟器 / 老游戏)
#
# 与既有工具分工: Steam 管 Steam 平台 (Proton); Bottles (Flatpak) 管单个
# Windows 应用; Lutris 管"散装"游戏 —— lutris.net 社区安装脚本自动建 wine
# 前缀 / 配 DXVK / 装运行库, 每个游戏可单独选 runner 与启动参数, 亦能挂载
# RetroArch/Dolphin 等模拟器。
#
# 运行前提 (均已在别处满足, 此处不重复声明):
# - 32 位图形栈: programs.steam 自动开 hardware.graphics.enable32Bit
#   (见 modules/nixos/steam.nix 头注释)
# - wine runner / DXVK 由 Lutris 自行下载到 ~/.local/share/lutris
#   (已在 persist.nix 声明持久化, 重装后免重下)
# - 性能工具 (mangohud / gamemode / gamescope) 当前未装: Lutris 按 PATH
#   检测, 装了才会出现对应开关, 需要时再补
{ pkgs, ... }:
{
  home.packages = [ pkgs.lutris ];
}
