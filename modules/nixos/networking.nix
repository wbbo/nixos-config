# 网络:主机名 / NetworkManager / 防火墙 / Wi-Fi
{ ... }:
{
  networking.hostName = "wbb";

  ### NetworkManager: 统一管理有线+无线+VPN
  networking.networkmanager.enable = true;

  ### 无线网络守护进程(NetworkManager 后端)
  # 已废弃 wireless.* 配置;Wi-Fi 由 NetworkManager 全权接管

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ]; # SSH
    allowedUDPPorts = [ ];
  };
}
