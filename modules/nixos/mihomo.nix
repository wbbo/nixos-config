# Mihomo 代理 (clash-meta 内核) + TUN 透明代理 + 系统 DNS
# 配置文件: /persist/etc/mihomo/config.yaml (跨重建持久化)
# config.yaml 需包含 routing-mark: 255 避免 mihomo 自身流量被 TUN 劫持造成死循环
{ lib, ... }:
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
    # GeoIP/GeoSite/缓存 持久化到 @persist: 重建系统后无需重新下载
    BindPaths = [
      "/persist/etc/mihomo/data:/var/lib/mihomo"
    ];
  };

  # 确保持久化目录在 BindPaths 前存在
  # tmpfiles 阶段 mihomo 用户尚未创建 (DynamicUser), 用 root 创建后
  # systemd 会在服务启动时 chown 到动态 uid (StateDirectory 机制)
  #
  # 注意: BindPaths 把此目录绑定到服务内 /var/lib/mihomo, mihomo 需写入
  # GeoIP MMDB / cache.db。DynamicUser 的 uid 动态, 无法用静态属主,
  # 且 StateDirectory 机制只 chown /var/lib/mihomo(宿主) 而不 chown 本目录,
  # 故用 0777 (目录仅存可重新下载的 GeoIP/缓存, 非敏感)。
  # 首次使用需在 /persist/etc/mihomo/data 放置 geoip.dat/metadb/geosite.dat
  # (可由 mihomo 自动下载, 或从旧主机复制)。
  systemd.tmpfiles.rules = [
    "d /persist/etc/mihomo/data 0777 root root - -"
  ];

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

  # 系统 DNS 不经过 mihomo: 使用 Cloudflare 直连
  # mihomo config.yaml 中 default-nameserver: ["system", …] 依赖系统 DNS
  # 如果系统 DNS = 127.0.0.1, mihomo 启动时自己还没监听 53 端口,
  # 解析 github.com 下载 GeoIP MMDB 就会失败 → 启动崩溃。
  # LAN 设备 DNS 通过 dns-hijack + TUN 仍由 mihomo 接管。
  networking.networkmanager.insertNameservers = [ "1.1.1.1" "1.0.0.1" ];
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
}
