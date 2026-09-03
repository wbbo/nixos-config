# Mihomo 代理 (clash-meta 内核) + TUN 透明代理 + 系统 DNS
# 配置文件: activation 生成到 /run/mihomo/config.yaml (tmpfs 无持久残留,
# 含订阅凭据经 LoadCredential 挂载供 DynamicUser 读取)
# 配置模板: mihomo.template.yaml (同目录)
# WebUI: 本地托管 (默认 metacubexd, 可用 mihomo-ui 选项切换 yacd/zashboard),
#        浏览器开 http://127.0.0.1:9090/ui (external-ui)
# config.yaml 需包含 routing-mark: 255 避免 mihomo 自身流量被 TUN 劫持造成死循环
{ config, lib, pkgs, ... }:
let
  # 规则集清单 (单点维护): 模板 rule-providers 段与缓存预拉均由此生成 (见下)。
  # mihomo 的 rule-provider url 只支持单 string (无数组 fallback, 实测 -t 拒绝),
  # 单域名 CDN 挂且本地缓存空 → 对应 RULE-SET 静默不存在、规则落空直落
  # MATCH,PROXY (LAN DIRECT 失效/全量进代理)。兜底: 激活期按 ruleSetUrls 三 CDN
  # 轮流预拉本地缓存 (/persist/var/lib/mihomo/ruleset, BindPaths 持久), 缓存永不为
  # 空; mihomo 启动后再按 interval 自身刷新。file 为 Loyalsoldier/clash-rules
  # @release 分支的清单文件名。
  ruleProviders = [
    { name = "reject"; behavior = "domain"; file = "reject.txt"; }
    { name = "icloud"; behavior = "domain"; file = "icloud.txt"; }
    { name = "apple"; behavior = "domain"; file = "apple.txt"; }
    { name = "google"; behavior = "domain"; file = "google.txt"; }
    { name = "proxy"; behavior = "domain"; file = "proxy.txt"; }
    { name = "direct"; behavior = "domain"; file = "direct.txt"; }
    { name = "private"; behavior = "domain"; file = "private.txt"; }
    { name = "gfw"; behavior = "domain"; file = "gfw.txt"; }
    { name = "tld-not-cn"; behavior = "domain"; file = "tld-not-cn.txt"; }
    { name = "telegramcidr"; behavior = "ipcidr"; file = "telegramcidr.txt"; }
    { name = "cncidr"; behavior = "ipcidr"; file = "cncidr.txt"; }
    { name = "lancidr"; behavior = "ipcidr"; file = "lancidr.txt"; }
    { name = "applications"; behavior = "classical"; file = "applications.txt"; }
  ];
  # 同一 GitHub 内容的三个独立 CDN 域名 (jsdelivr cdn/fastly/gcore)
  ruleSetUrls = p: [
    "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/${p.file}"
    "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/${p.file}"
    "https://gcore.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/${p.file}"
  ];
  # 模板 $RULE_PROVIDERS 占位: mihomo 段用主域名单 url, 缓存兜底在预拉
  ruleProviderYaml = lib.concatMapStringsSep "\n"
    (p: "  ${p.name}: {type: http, behavior: ${p.behavior}, url: \"${builtins.head (ruleSetUrls p)}\", path: ./ruleset/${p.name}.yaml, interval: 86400}")
    ruleProviders;
  # 激活期预拉调用行 (shell 引号内嵌 URL, 无特殊字符风险)
  prefillCmds = lib.concatMapStrings
    (p: "  prefill \"${p.name}.yaml\" ${lib.concatMapStringsSep " " (u: "'${u}'") (ruleSetUrls p)}\n")
    ruleProviders;

  # WebUI 面板包 (本地托管, 经激活脚本链接到 /persist/var/lib/mihomo/ui)
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
      # config 由 activation 生成到 /run (tmpfs, 无持久残留): 含订阅凭据,
      # 经 LoadCredential 挂到 /run/credentials/mihomo.service/ 供 DynamicUser 读取
      configFile = "/run/mihomo/config.yaml";
      tunMode = true;
    };

    # 部署时自动生成 config.yaml 到 /run/mihomo/: 模板 + sops 订阅 URL 列表。
    # 为什么用 activation 而非 preStart: 模块的 LoadCredential 在服务启动最早阶段
    # (ExecStartPre 之前) 挂载配置, preStart 生成的文件来不及; activation 在系统
    # 激活期运行, 早于任何服务启动, 时序满足。config 落 /run (tmpfs) 而非持久层:
    # 配置本质无状态, 每次开机/rebuild 重新生成, 无残留。
    # 依赖 setupSecrets (sops 解密全部 secret) 之后运行; setupSecretsForUsers 只解
    # neededForUsers, 冷启动时 mihomo 的 secret 未就绪会回退占位。
    system.activationScripts.mihomo-config = lib.stringAfter [ "var" "setupSecrets" ] ''
      mkdir -p /run/mihomo
      # 规则集缓存预拉: mihomo 的 rule-provider 只支持单 url (不支持数组
      # fallback, 实测 -t 拒绝), 缓存为空的首次安装/清 persist 后若恰逢 CDN
      # 不可达, 对应 RULE-SET 静默不存在 (规则落空直落 MATCH,PROXY)。
      # 激活期先按三 CDN 轮流铺满缓存, 此后 interval 内断网也靠缓存续命;
      # 失败留 marker 不重复试, 留给 mihomo 启动后自刷新。目录 0777: mihomo
      # DynamicUser 刷新规则集时在目录内 rename 覆盖, 需要写权限 (动态 uid
      # 无法静态 chown, 同父目录理由; 内容可重新下载非敏感)。
      RULESET_DIR=/persist/var/lib/mihomo/ruleset
      mkdir -p "$RULESET_DIR"
      chmod 0777 "$RULESET_DIR"
      prefill() {
        local cache="$1"
        local marker="$RULESET_DIR/.prefill-$1"
        shift
        [ -s "$RULESET_DIR/$cache" ] && { rm -f "$marker"; return 0; }
        # marker 24h 内跳过 (CDN 全挂时避免每次激活耗 3×curl 超时); 超龄重试:
        # 缓存被删后 mihomo 自下载也可能失败 (单 url 无镜像), 预拉需重拾
        if [ -e "$marker" ]; then
          local now mtime
          now="$(${pkgs.coreutils}/bin/date +%s)"
          mtime="$(${pkgs.coreutils}/bin/stat -c %Y "$marker" 2>/dev/null || echo 0)"
          if [ "$mtime" -ge $((now - 86400)) ] 2>/dev/null; then
            return 0
          fi
          rm -f "$marker"
        fi
        local url
        for url in "$@"; do
          # max-time 60: 最大清单 reject.txt 5MB+, 差网络下 ~200KB/s 需 ~25s
          if ${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 60 -fsSL "$url" -o "$RULESET_DIR/$cache.tmp" 2>/dev/null \
              && [ -s "$RULESET_DIR/$cache.tmp" ]; then
            ${pkgs.coreutils}/bin/mv -f "$RULESET_DIR/$cache.tmp" "$RULESET_DIR/$cache"
            return 0
          fi
          rm -f "$RULESET_DIR/$cache.tmp"
        done
        touch "$marker"
        echo "警告: 规则集 $cache 预拉失败 (三 CDN 均不可达), mihomo 启动后自动重试" >&2
        return 1
      }
${prefillCmds}
      # secret 缺失时用占位(分发模板可构建), 正式机由 sops 提供
      # mihomo API secret 复用主用户密码; 该 secret 是 neededForUsers,
      # 实际位于 /run/secrets-for-users/ (经 sops.secrets...path 引用, 早于 users 段就绪)
      API_SECRET="$(cat ${config.sops.secrets.main-user-password.path} 2>/dev/null || echo 'changeme')"
      # 订阅 URL 列表: secret 值为 YAML 块标量字符串, 每行一条 URL (sops-nix 仅支持字符串 secret)
      # secret 缺失 (分发模板) → 空数组, 由下方占位兜底; sub("\\r$") 兼容 CRLF 行尾
      SUB_JSON="$(cat /run/secrets/mihomo-subscription-url 2>/dev/null \
        | ${pkgs.jq}/bin/jq -R -s 'split("\n") | map(sub("\\r$"; "") | select(length > 0))')"
      # 按列表顺序生成 provider1/provider2/... 段 (flow style 与 rule-providers 一致)
      PROVIDERS="$(printf '%s' "$SUB_JSON" | ${pkgs.jq}/bin/jq -r 'to_entries | map("  provider\(.key + 1): {url: \(.value | @json), type: http, interval: 14400}") | join("\n")')"
      # 空列表兜底占位, 避免生成空的 proxy-providers 段
      if [ -z "$PROVIDERS" ]; then
        echo "mihomo-subscription-url 为空或缺失, 使用占位订阅" >&2
        PROVIDERS='  provider1: {url: "https://YOUR-PROVIDER/SUBSCRIBE?token=REPLACE_ME", type: http, interval: 14400}'
      fi
      # 规则集段由 Nix 侧 ruleProviders 清单生成 (模板 $RULE_PROVIDERS 占位),
      # 与预拉同源单点维护
      RULE_PROVIDERS='${ruleProviderYaml}'
      export API_SECRET PROVIDERS RULE_PROVIDERS
      ${pkgs.envsubst}/bin/envsubst '$API_SECRET $PROVIDERS $RULE_PROVIDERS' < ${./mihomo.template.yaml} > /run/mihomo/config.yaml
      chmod 0600 /run/mihomo/config.yaml  # 含订阅 token/API secret, 仅 root 可读 (LoadCredential 由 root 读)
      # config 更新后重载 mihomo (绝对路径: activation PATH 无 systemd, 裸命令会 127)
      # 首次安装 (nixos-install chroot) 时 /run/current-system 尚未建立, 热重载无意义, 跳过
      # config 内容未变时跳过 restart: 每次 rebuild 无条件 restart 会重建 TUN 设备与
      # 策略路由, 窗口内直连流量被墙, 误伤同窗口的下载类激活钩子 (cc-switch/claude/nvm)
      # prev 同放 /run: 开机首次生成时 prev 不存在 → try-restart, 但 mihomo 未启动
      # (try-restart 对未运行服务是 no-op), 无副作用
      if [ -x /run/current-system/sw/bin/systemctl ]; then
        MIHOMO_CONFIG_PREV=/run/mihomo/config.yaml.prev
        if ! ${pkgs.diffutils}/bin/cmp -s /run/mihomo/config.yaml "$MIHOMO_CONFIG_PREV" 2>/dev/null; then
          ${pkgs.coreutils}/bin/cp /run/mihomo/config.yaml "$MIHOMO_CONFIG_PREV"
          /run/current-system/sw/bin/systemctl try-restart mihomo
        fi
      fi
    '';

    # 本地托管 WebUI: 所选面板链接到 /persist/var/lib/mihomo/ui,
    # 经下方 BindPaths(/persist/var/lib/mihomo→/var/lib/private/mihomo) 出现在服务内
    # /var/lib/private/mihomo/ui (模块 ExecStart 的 -d 数据目录), config.yaml 的
    # external-ui: ./ui 相对 -d 解析, 路径匹配。
    # 数据按 FHS 落 /persist/var/lib/mihomo (状态数据在 /var/lib, 与
    # /persist/var/lib/nixos 同先例); config.yaml 在 /run (无持久残留)。
    system.activationScripts.mihomo-ui = lib.stringAfter [ "var" ] (
      let ui = uis.${config.mihomo-ui}; in ''
        mkdir -p /persist/var/lib/mihomo
        ln -sfn ${ui} /persist/var/lib/mihomo/ui
      ''
    );

    # 本机 fake-ip 闭环配套 (dns.listen ":53" 在模板, 兼路由器/旁路由):
    # nameservers + NM dns=none 让本机查询全量到 mihomo; NM 不拦截时 DHCP 的
    # 网关 DNS 会混入 resolv.conf, 分流时真时假。mihomo 挂则解析挂, 明确取舍。
    networking.networkmanager.dns = "none";

    # 路由器/旁路由场景: LAN 设备把 DNS 指向本机 :53 的查询入口 (INPUT 链;
    # 设备流量本身走转发/FORWARD 链, 由 TUN 的 nft 规则接管, 不经此清单)
    networking.firewall.allowedUDPPorts = [ 53 ];
    networking.firewall.allowedTCPPorts = [ 53 ];

    # 允许 DynamicUser=mihomo 绑定 53 端口 (DNS) + 操作 TUN 设备
    systemd.services.mihomo.serviceConfig = {
      AmbientCapabilities = lib.mkForce "CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW";
      CapabilityBoundingSet = lib.mkForce "CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW";
      # gVisor netstack 需要 epoll_wait 等不在 @system-service 白名单中的 syscall
      SystemCallFilter = lib.mkForce [];
      # 状态数据持久化: 模块 ExecStart 用 -d /var/lib/private/mihomo (DynamicUser 的
      # StateDirectory 位于 /var/lib/private/<name>), 直接映射 /persist/var/lib/mihomo
      # 到该路径 (结构一致, 零概念转换); ruleset 缓存/cache.db/ui 相对 -d 解析,
      # 经 BindPaths 落持久层。
      BindPaths = [
        "/persist/var/lib/mihomo:/var/lib/private/mihomo"
      ];
    };

    # 首次安装后的 HM 激活会触发工具安装钩子 (claude/codex/cc-switch),
    # 钩子探测 127.0.0.1:7890 走代理下载 —— mihomo 必须先行, 否则直连被墙必失败。
    # After= 仅排序不阻塞: mihomo 起不来 (如 secrets 未初始化, 无订阅配置) 时
    # HM 照常激活, 工具由 timeout 兜底记警告, 初始化 secrets 后 rebuild 补装。
    systemd.services."home-manager-${config.mainUser}".after = [ "mihomo.service" ];

    # 确保持久化目录在 BindPaths 前存在
    # tmpfiles 阶段 mihomo 用户尚未创建 (DynamicUser), 用 root 创建后
    # systemd 会在服务启动时 chown 到动态 uid (StateDirectory 机制)
    #
    # 注意: BindPaths 把此目录绑定到服务内 /var/lib/mihomo, mihomo 需写入
    # cache.db/ruleset 缓存。DynamicUser 的 uid 动态, 无法用静态属主,
    # 且 StateDirectory 机制只 chown /var/lib/mihomo(宿主) 而不 chown 本目录,
    # 故用 0777 (目录仅存可重新下载的规则集缓存/订阅缓存, 非敏感)。
    # GEOIP/GEOSITE 数据库不再需要: 规则集化 (RULE-SET cncidr/private 等替代
    # GEOIP 规则), 零 geo 文件依赖, 启动不联网下载 (见 mihomo.template.yaml)。
    systemd.tmpfiles.rules = [
      "d /persist/var/lib/mihomo 0777 root root - -"
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

    # 系统 DNS: mihomo 主解析 + 异常兜底 (恰好 3 条 = glibc MAXNS 上限)。
    # resolv.conf 静态化: NM dns=none 后本不需要 resolvconf 的动态合并, 且
    # openresolv 的 local_only 过滤 (默认只要列表里出现 127.0.0.1, 非 127.x
    # 上游一概丢弃) 会把兜底条目在每次 resolvconf -u 后吞掉 —— 直接写静态
    # 文件, 同时关掉 resolvconf (其 wrapper 变为显式报错, dispatcher 不再装)。
    networking.resolvconf.enable = false;
    environment.etc."resolv.conf".text = ''
      nameserver 127.0.0.1
      nameserver 1.1.1.1
      nameserver 8.8.8.8
      options edns0
    '';
  };
}
