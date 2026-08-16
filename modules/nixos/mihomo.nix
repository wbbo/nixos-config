# Mihomo 代理 (clash-meta 内核) + TUN 透明代理 + 系统 DNS
# 配置文件: /persist/etc/mihomo/config.yaml (跨重建持久化)
# 配置模板: mihomo.template.yaml (同目录, 填订阅后复制到上面路径)
# WebUI: 本地托管 (默认 metacubexd, 可用 mihomo-ui 选项切换 yacd/zashboard),
#        浏览器开 http://127.0.0.1:9090/ui (external-ui)
# config.yaml 需包含 routing-mark: 255 避免 mihomo 自身流量被 TUN 劫持造成死循环
{ config, lib, pkgs, ... }:
let
  # WebUI 面板包 (本地托管, 经激活脚本链接到 /persist/etc/mihomo/data/ui)
  uis = {
    # nixpkgs 自带, 官方适配 mihomo
    metacubexd = pkgs.metacubexd;
    # 经典面板: 构建产物在 gh-pages 分支 (haishanh/yacd)
    yacd = pkgs.fetchFromGitHub {
      owner = "haishanh";
      repo = "yacd";
      rev = "09eb9389a7109eafd35118cbf7c2ac0860190b01";
      sha256 = "0lcfv7q500ib2zc619dih02l6441s80mrw38kbxfnxq6d5inr9a9";
    };
    # 现代风格: 构建产物在 gh-pages 分支 (Zephyruso/zashboard)
    zashboard = pkgs.fetchFromGitHub {
      owner = "Zephyruso";
      repo = "zashboard";
      rev = "3ca08fe14748c686c65c8e6987191b32490a7101";
      sha256 = "07kdpjkqw11mbx0b9p6r588687h6ln001hhp7n5gacwmaib9nycx";
    };
  };
in {
  options.mihomo-ui = lib.mkOption {
    type = lib.types.enum [ "metacubexd" "yacd" "zashboard" ];
    default = "metacubexd";
    description = "mihomo WebUI 面板 (本地托管): metacubexd / yacd / zashboard";
  };

  config = {
    services.mihomo = {
      enable = true;
      configFile = "/persist/etc/mihomo/config.yaml";
      tunMode = true;
    };

    # 部署时自动生成 config.yaml: 模板 + sops 订阅 URL (secret 解密到 /run/secrets)
    # 替代手动放置; 换机场只改 secrets.yaml, 其他配置改 mihomo.template.yaml。
    # 依赖 setupSecrets (sops 解密全部 secret) 之后运行; setupSecretsForUsers 只解 neededForUsers,
    # 冷启动时 mihomo 的 secret 未就绪会回退占位。
    system.activationScripts.mihomo-config = lib.stringAfter [ "var" "setupSecrets" ] ''
      mkdir -p /persist/etc/mihomo
      # secret 缺失时用占位(分发模板可构建), 正式机由 sops 提供
      SUB_URL="$(cat /run/secrets/mihomo-subscription-url 2>/dev/null || echo 'https://YOUR-PROVIDER/SUBSCRIBE?token=REPLACE_ME')"
      API_SECRET="$(cat /run/secrets/mihomo-api-secret 2>/dev/null || echo 'changeme')"
      export SUB_URL API_SECRET
      ${pkgs.envsubst}/bin/envsubst '$SUB_URL $API_SECRET' < ${./mihomo.template.yaml} > /persist/etc/mihomo/config.yaml
      chmod 0600 /persist/etc/mihomo/config.yaml  # 含订阅 token/API secret, 仅 root 可读 (LoadCredential 由 root 读)
      # config 更新后重载 mihomo (绝对路径: activation PATH 无 systemd, 裸命令会 127)
      /run/current-system/sw/bin/systemctl try-restart mihomo
    '';

    # 本地托管 WebUI: 所选面板链接到 /persist/etc/mihomo/data/ui,
    # 经下方 BindPaths(data→/var/lib/mihomo) 出现在服务内 /var/lib/mihomo/ui,
    # config.yaml 的 external-ui 指向该固定路径 (随 rebuild 更新, 无残留)。
    system.activationScripts.mihomo-ui = lib.stringAfter [ "var" ] (
      let ui = uis.${config.mihomo-ui}; in ''
        mkdir -p /persist/etc/mihomo/data
        ln -sfn ${ui} /persist/etc/mihomo/data/ui
      ''
    );

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
  };
}
