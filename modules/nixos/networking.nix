# 网络:主机名 / NetworkManager / 防火墙 / Wi-Fi
# hostName 默认取 flake.nix 传入值, 每台机器可在 hosts/<hostDir>/local.nix 中覆盖
{ config, lib, hostName, ... }:
{
  options.hostName = lib.mkOption {
    type = lib.types.str;
    default = hostName;
    description = "主机名 (默认 flake.nix 的 hostName; 每台机器可在 hosts/<hostDir>/local.nix 覆盖)";
  };

  # 模块含顶层 options 时, 配置属性必须全部移入 config
  config = {
    networking.hostName = config.hostName;

    ### NetworkManager: 统一管理有线+无线+VPN
    networking.networkmanager.enable = true;

    ### 无线网络守护进程(NetworkManager 后端)
    # 已废弃 wireless.* 配置;Wi-Fi 由 NetworkManager 全权接管

    networking.firewall = {
      enable = true;
      # 22 全局放行 —— 端口可达性与认证强度是两个独立维度: 认证层收紧为
      # key-only + 临时密码开关 (见 services.nix / ssh-temp-password.nix),
      # 不做来源 IP 限制 (曾按固定管理机白名单过, DHCP 换地址即失联, 已撤)。
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ ];
    };
  };
}
