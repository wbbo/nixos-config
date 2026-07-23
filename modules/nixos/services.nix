# 系统服务:SSH / 蓝牙 / 电源
{ ... }:
{
  services.openssh.enable = true;
  services.blueman.enable = true;
  services.power-profiles-daemon.enable = true;
}
