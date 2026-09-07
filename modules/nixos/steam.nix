# Steam 游戏平台 (NixOS 系统级, 32 位图形依赖)
#
# nixpkgs steam 模块自动处理: hardware.graphics.enable32Bit、steam-hardware、
# pipewire ALSA 32 位支持 —— 此处无需重复声明。
# 运行栈: Steam 为 X11 客户端 → 需 XWayland (xwayland-satellite, home 层
# niri.nix 注入 PATH, niri 26.04 按需自动 spawn)。RTX 4090 (nvidia open 模块,
# modesetting/GBM) 已满足, 无需额外配置。
{ config, lib, ... }:
{
  programs.steam = {
    enable = true;
    # 局域网内 P2P 传输 (同网 PC 互拷游戏), 自动开 TCP 27036;
    # 互联网多人联机端口 (UDP 27000-27100 等) 默认不开 —— 需要的游戏
    # 会在首次联机失败时提示, 届时按需在 local.nix 加 allowedUDPPorts。
    localNetworkGameTransfers.openFirewall = lib.mkDefault true;
  };
}
