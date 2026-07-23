# 硬件:图形、蓝牙
{ pkgs, ... }:
{
  ### 图形加速(NixOS 24.11+ 用 hardware.graphics 替代旧 hardware.opengl)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # Wine 32位游戏需要
    extraPackages = with pkgs; [
      intel-media-driver  # Intel VA-API 硬件视频解码
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver  # 32位 VA-API(Wine兼容层)
    ];
  };

  ### 蓝牙
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
}
