# Mihomo 代理 (clash-meta 内核) + TUN 透明代理 + 系统 DNS
# 配置文件: /persist/etc/mihomo/config.yaml (跨重建持久化)
# config.yaml 需包含 routing-mark: 255 避免 mihomo 自身流量被 TUN 劫持造成死循环
{ config, lib, ... }:
{
  services.mihomo = {
    enable = true;
    configFile = "/persist/etc/mihomo/config.yaml";
    tunMode = true;
  };

  # 允许 DynamicUser=mihomo 绑定 53 端口 (DNS) + 操作 TUN 设备
  systemd.services.mihomo.serviceConfig = {
    AmbientCapabilities = lib.mkForce "CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW";
    CapabilityBoundingSet = lib.mkForce "CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW";
    # gVisor netstack 需要 epoll_wait 等不在 @system-service 白名单中的 syscall
    SystemCallFilter = lib.mkForce [];
  };

  # TUN 需要 ip_forward=1 (mixed/system 栈通过内核 TUN 设备路由)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # === TUN 防火墙兼容 (参考 nixpkgs PR #517118) ===
  # NixOS 默认 nftables + rp_filter=2 会丢弃 TUN 接口上源 IP 为
  # private/fake-ip 范围的数据包, 导致 TCP 连接无法建立。
  networking.firewall.checkReversePath = "loose";
  networking.firewall.trustedInterfaces = [ "Mihomo" ];

  # 系统 DNS 解析由 mihomo 接管 (fake-ip, 127.0.0.1:53)
  # NetworkManager 不再下发 DHCP DNS, 所有连接统一使用 mihomo DNS。
  # 如果 mihomo 崩溃，NetworkManager 自动使用 DHCP 提供的 DNS 作为 fallback
  # (insertNameservers 仅在 NetworkManager 在线时有效，nameservers 永久写入 /etc/resolv.conf，
  # 两者同时配置确保多一层兜底，避免 mihomo 故障导致全系统 DNS 不可用)。
  networking.networkmanager.insertNameservers = [ "127.0.0.1" ];
  networking.nameservers = [ "127.0.0.1" "223.5.5.5" ];
}
