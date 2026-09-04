#!/usr/bin/env bash
# NixOS 安装脚本 —— disko 分区 + nixos-install
# 用法: sudo ./scripts/install.sh --disk /dev/sdb [-f]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# 公共函数 (info/warn/die/host_name/host_dir), 与 scripts/ 下脚本共用
source "$SCRIPT_DIR/scripts/common.sh"

SCRIPT_NAME="$(basename "$0")"

DISK=""
FORCE=0   # -f/--force: 跳过磁盘确认 (README 记载的无人值守入口)

# 主机名/主机目录自动从 flake.nix 读取 (networking.hostName 可在 local.nix 覆盖;
# 解析逻辑见 scripts/common.sh 的 host_name/host_dir)
HOST_NAME="$(host_name)"
HOST_DIR="$(host_dir)"

if ! TEMP=$(getopt -o d:fh --long disk:,force,help -n "$SCRIPT_NAME" -- "$@"); then
  echo "参数解析错误" >&2; exit 1
fi
eval set -- "$TEMP"

while true; do
  case "$1" in
    -d|--disk) DISK="$2"; shift 2 ;;
    -f|--force) FORCE=1; shift ;;
    -h|--help) exit 0 ;;   # 帮助职责在统一入口 build.sh -h, 此处静默退出
    --) shift; break ;;
    *) echo "未知选项: $1" >&2; exit 1 ;;
  esac
done

# 允许位置参数作为磁盘设备的快捷方式
REMAINING_ARGS=("$@")
if [ -z "$DISK" ] && [ ${#REMAINING_ARGS[@]} -gt 0 ]; then
  DISK="${REMAINING_ARGS[0]}"
  [ ${#REMAINING_ARGS[@]} -gt 1 ] && warn "多余的参数将被忽略, 仅使用 $DISK"
fi

[ -n "$DISK" ] || die "缺少 --disk 参数 (安装用法见 ./build.sh -h)"
[ -b "$DISK" ] || die "磁盘 $DISK 不存在"
[ "$(id -u)" = 0 ] || die "请用 sudo 运行"

# ---- Live CD 环境守卫: 已装系统上误跑本脚本会 zap 全盘摧毁数据 ----
# 判据: Live 根为 tmpfs 或存在 /nix/.ro-store (ISO squashfs store 层);
# 已装系统 (磁盘文件系统根 + 无 overlay store) 两者皆假 → 拒绝并指引
# 统一入口 build.sh (环境感知, Live 自动转安装、已装走日常重建)。
if [ "$(findmnt -no FSTYPE / 2>/dev/null || true)" != "tmpfs" ] && [ ! -d /nix/.ro-store ]; then
  die "非 Live CD 环境! install.sh 会全盘清空; 日常重建请用 ./build.sh"
fi

# ---- 临时禁用 systemd-oomd: 低内存 VM 防护误杀 (脚本最前, 覆盖所有阶段) ----
# 3.8G VM 实测: nix 求值/构建进程在内存整体 ~85% 时被 systemd-oomd 击杀
# (cgroup 压力触发, 峰值仅 490MB 也照杀, 无 OOM 记录无输出, 静默消失)。
# 放参数校验后、一切 nix 调用前: 从 sops 解密的 nix shell 到预热构建/
# nixos-install 的全部内存峰值阶段都在保护范围。不恢复: Live CD 是临时
# 环境 (tmpfs), 安装完成后 reboot 即弃, 新系统从自身配置启动, oomd 状态
# 由 NixOS 声明式管理。停用失败仅 warn: 无碍继续 (真 OOM 由内核兜底)。
if systemctl stop systemd-oomd 2>/dev/null; then
  info "已停用 systemd-oomd (Live CD 临时环境, 防止OOM)"
else
  warn "停用 systemd-oomd 失败 (可能未启用), nix 进程仍可能被 oomd 击杀"
fi

# 解析真实设备名 (处理 /dev/disk/by-id 等符号链接)
REAL_DISK=$(readlink -f "$DISK" 2>/dev/null || echo "$DISK")

# ---- 通用重试 (预热构建/nixos-install 共用; 可被环境变量覆盖) ----
# RETRY_N=20 ./install.sh -d /dev/sda 即可调整; 设非 0 值恢复次数上限
RETRY_N="${RETRY_N:-0}"           # 各阶段最大尝试次数; 0 (默认) = 无限重试, Ctrl-C 随时中止
# 非法值 (负数/垃圾) 不静默当无限 —— 语义错位比显式失败更难排查
case "$RETRY_N" in ''|*[!0-9]*) die "RETRY_N 须为非负整数 (0=无限重试), 当前: $RETRY_N" ;; esac
RETRY_WAIT_S="${RETRY_WAIT_S:-15}"  # 重试间隔秒 (被杀进程内存即时释放, 短等待足够)
retry() {
  # retry <阶段描述> <命令 [args...]>: 失败自动重试, RETRY_N 有限时耗尽返回最后一次 rc。
  # 适用增量语义命令 —— store 内容/已下载闭包跨重试保留, 后续尝试只补差量。
  # 默认无限重试: 低内存机 nix daemon 被压死的轮次不可预估 (实测封顶内第 9/10
  # 次仍倒在半途), Ctrl-C (rc=130) 是随时可用的中止途径。
  local desc="$1"; shift
  local attempt=0 rc=1
  while :; do
    attempt=$((attempt + 1))
    info "$desc 第 $attempt 次 (Ctrl-C 可中止; 长时静默属正常, 勿中断)..."
    if "$@"; then
      return 0
    else
      rc=$?
    fi
    warn "$desc 退出 (rc=$rc)"
    # SIGINT (Ctrl-C, rc=130) 是用户主动中止, 不允许重试拉起下一轮
    # (实测 ^C 后 retry 继续跑, 用户需连按多次才能退出)
    if [ "$rc" = 130 ]; then
      die "$desc 被用户中断 (Ctrl-C), 已停止重试"
    fi
    if [ "$RETRY_N" -gt 0 ] 2>/dev/null && [ "$attempt" -ge "$RETRY_N" ]; then
      return "$rc"
    fi
    warn "  ${RETRY_WAIT_S}s 后自动重试 (增量保留, 已完成部分不重复)..."
    # 清 nix fetcher 缓存: 首拉撞网络坏窗口时损坏结果会被缓存毒化, 命中
    # 毒化缓存的重试永不自愈 (实测 "flake.nix does not exist" 同错循环)
    rm -f /root/.cache/nix/fetcher-cache-v4.sqlite
    sleep "$RETRY_WAIT_S"
  done
}

# ---- 仓库自带 mihomo (可选): 安装最前置代理 ----
# mihomo/ (静态链接二进制 + 完整配置, gitignored, 使用者自行放置到仓库根) 存在时,
# 在安装流程最前面拉起, 并把本次安装的全部网络拉取 (disko/nixos-install/sops
# shell 等所有 nix 子进程) 导到它的 mixed-port 7890 —— Live CD 直连被墙环境
# (GitHub/nix cache 等) 靠它出网。拉起失败不阻断安装 (仅失去代理, 直连可用时
# 照常); 安装结束不 kill, 进程随 Live CD 会话结束 (reboot) 自然消失。
# 走显式代理环境变量而非依赖 TUN 透明接管: Live CD 的 /etc/resolv.conf 默认
# 指向网关 DNS, 解析返回真实 IP, TUN 侧只见 IP 按地址分流会误判直连 (实测
# cache.nixos.org 经 TUN 直连超时, 同节点显式代理传域名则 200 —— mihomo 按
# 域名规则兜底走代理); 脚本会在 mihomo 就绪后把 /etc/resolv.conf 指向
# 127.0.0.1 (NM 覆盖时仅告警, 环境变量兜底), TUN + 显式代理双通道出网。
MIHOMO_DIR="$SCRIPT_DIR/mihomo"
# 二进制经 scp/解压等方式拷入易丢可执行位 (gitignored 不受 git 管理), 存在即补
# (脚本体已强制 root, chmod 必成功; 失败仅回退原 -x 判据)
if [ -f "$MIHOMO_DIR/mihomo" ] && [ ! -x "$MIHOMO_DIR/mihomo" ]; then
  chmod +x "$MIHOMO_DIR/mihomo" 2>/dev/null || true   # set -e 下失败只回退 -x 判据
fi
if [ -x "$MIHOMO_DIR/mihomo" ]; then
  if ss -tln 2>/dev/null | grep -q ':7890 '; then
    info "mihomo 已在运行 (port 7890), 复用为安装代理"
    export_use_mihomo=1
  else
    info "检测到仓库自带 mihomo, 启动安装期代理..."
    nohup ./mihomo/mihomo -d ./mihomo >mihomo/mihomo.log 2>&1 &
    # 等待 mix-port 就绪 (最多 ~5s); if 形式防 grep 不匹配触发 set -e 退出
    for i in 1 2 3 4 5; do
      if ss -tln 2>/dev/null | grep -q ':7890 '; then
        break
      fi
      sleep 1
    done
    if ss -tln 2>/dev/null | grep -q ':7890 '; then
      info "mihomo 就绪: TUN + mixed-port 7890 (日志: mihomo/mihomo.log)"
      export_use_mihomo=1
    else
      warn "mihomo 5s 内未就绪 (架构不符/配置错误?), 安装继续 (无代理)"
      warn "  排查: cat $MIHOMO_DIR/mihomo.log"
    fi
  fi
  if [ "${export_use_mihomo:-0}" = 1 ]; then
    # Live CD 防火墙默认拒绝入站 (NixOS networking.firewall 默认开启, ISO 只读
    # 无法改 allowedTCPPorts), 运行时 iptables 放行代理/控制端口供 LAN 访问;
    # 失败不阻断 (仅 LAN 不可达, 本机代理不受影响)
    if command -v iptables >/dev/null 2>&1 \
       && iptables -I INPUT -p tcp --dport 7890 -j ACCEPT 2>/dev/null \
       && iptables -I INPUT -p tcp --dport 9090 -j ACCEPT 2>/dev/null; then
      info "防火墙已放行入站 7890/9090 (tcp), LAN 可访问"
      # 控制 API 在 config.yaml 只绑 127.0.0.1:9090 (回环), LAN 面板访问经
      # PREROUTING DNAT 转到回环; conntrack 自动回程, 无需额外规则。失败仅
      # LAN 面板不可达, 本机 API/代理不受影响。Live CD 重启后规则消失 (临时)。
      # DNAT 到 127.0.0.1 的包默认被内核判 martian 丢弃 (route_localnet=0),
      # LAN→:9090 静默不通 (实测踩坑); 显式放行 127/8 经非 lo 接口
      sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null 2>&1 \
        || warn "route_localnet=1 设置失败, LAN 访问面板可能不通"
      if iptables -t nat -A PREROUTING -p tcp --dport 9090 \
           -j DNAT --to-destination 127.0.0.1:9090 2>/dev/null; then
        info "控制 API DNAT 已配置: LAN :9090 → 127.0.0.1:9090"
      else
        warn "控制 API DNAT 失败, LAN 面板可能不可达 (本机 API 不受影响)"
      fi
    else
      warn "防火墙放行不可用/失败, LAN 访问可能不通 (本机代理不受影响)"
    fi
    # 控制面板 (external-controller 绑 127.0.0.1:9090 + secret; LAN 经上方 DNAT
    # 访问): 安装期可从局域网另一台机器开面板切节点
    if ss -tln 2>/dev/null | grep -q ':9090 '; then
      LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
      info "控制 API 就绪: 本机 http://127.0.0.1:9090/ui, LAN http://${LAN_IP}:9090/ui (secret 同 mihomo/config.yaml)"
    fi
    # TUN 透明代理需要本机 DNS 指向 mihomo (fake-ip 入口): NM 的 rc-manager=
    # resolvconf 模式下 /etc/resolv.conf 是独立文件, 直接写入。三条与生产
    # resolv.conf (mihomo.nix) 同构: 127.0.0.1 主解析 + 1.1.1.1/8.8.8.8 兜底
    # (glibc MAXNS=3 恰好满额) —— mihomo DNS 侧异常时 127.0.0.1 快速失败,
    # 兜底查询出网被 TUN dns-hijack 劫持仍回到 mihomo。NM 重新生成 (link 变化/
    # DHCP 续约) 会覆盖回网关 DNS —— 失败仅告警, 此时 fake-ip 断供, 由下方
    # 环境变量兜底 (nix 拉取确定可用); 面板切节点后可重试
    if printf 'nameserver 127.0.0.1\nnameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf 2>/dev/null \
       && grep -q '127.0.0.1' /etc/resolv.conf; then
      info "已设置本机 DNS: 127.0.0.1 主解析 (mihomo fake-ip 入口) + 1.1.1.1/8.8.8.8 兜底"
    else
      warn "无法写入 /etc/resolv.conf, 本机 DNS 保持网关 -> TUN 降级 IP 分流 (环境变量兜底不受影响)"
    fi
    # TUN 透明代理已覆盖全部出站 (gvisor 栈读 TUN 包 → fake-ip 域名分流):
    # 实测无环境变量时 cache.nixos.org/github/channels/api.github.com 全通。
    # https_proxy 仅作冗余保险 —— TUN 依赖 listen(127.0.0.1:53) + resolv.conf
    # (上面刚设置) + fake-ip 路由覆盖; 若任一环节缺失 (NM 覆盖 resolv.conf、
    # Live CD 重启后运行态丢失), 显式代理仍是确定可用的兜底路径 (传域名给
    # mihomo, 不经本机 DNS)。留着无害 (no_proxy 已排除本机端口), 确定性优先。
    # 防火墙放行供 LAN 访问面板/代理 (Live CD 只读, 只能运行时 iptables)
    export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
    export no_proxy=localhost,127.0.0.1
    info "TUN 透明代理已接管 (实测全链 200), 环境变量作冗余兜底 (7890, no_proxy=localhost)"
  fi
fi

echo ""
warn "即将清空 $DISK 全盘数据!"
lsblk -o NAME,SIZE,TRAN,MODEL "$REAL_DISK"
echo ""
# 交互下回车 = 默认确认 (Y); n/N 取消。read 失败 (非交互 EOF, 如管道/CI)
# 一律取消 —— 全盘 wipe 必须有人工在场, 不因回车默认而放行无人场景;
# -f/--force 为唯一跳过途径 (Live CD 环境守卫与显式 --disk 仍在前置把关)。
if [ "$FORCE" = 1 ]; then
  warn "-f 已跳过磁盘确认"
else
  printf "即将清空 %s 全盘数据, 继续? [Y/n] " "$DISK"
  if read -r confirm; then
    case "${confirm:-Y}" in
      [Yy]) : ;;
      *) info "已取消"; exit 0 ;;
    esac
  else
    info "非交互输入, 已取消"; exit 0
  fi
fi

# ============================================================================
# 阶段 1: 环境准备
# ============================================================================
info "[1/4] 环境检查"
MEM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}' 2>/dev/null || echo 4096)
info "可用内存: ${MEM_MB}M"

if [ "$MEM_MB" -lt 7680 ]; then
  warn "内存不足 7.5G (7680M), 创建临时 zram"
  # zram 阈值 7680 (而非 8192): 8G 整内存机不建 (8192 ≥ 7680), 7.5-8G 之间
  # 也不建 —— 留 0.5G 余量, 与下方 max-jobs/tmpfs 的 8192 低内存分档各有
  # 语义 (zram 更保守: 不足 7.5G 才需要压缩交换兜底)。
  # zram 大小按内存 50% 缩放 (与系统 zramSwap 50% 一致), 上下限钳制:
  # 下限 512M 保证最小可用; 上限 4G 防大内存机上喧宾夺主 (系统还有与内存等大的 swapfile 兜底)
  ZRAM_MB=$((MEM_MB / 2))
  [ "$ZRAM_MB" -gt 4096 ] && ZRAM_MB=4096
  [ "$ZRAM_MB" -lt 512 ] && ZRAM_MB=512
  if modprobe zram 2>/dev/null; then
    [ -e /dev/zram0 ] && { swapoff /dev/zram0 2>/dev/null || true; echo 1 > /sys/block/zram0/reset 2>/dev/null || true; }
    [ -e /sys/block/zram0/disksize ] && { echo "${ZRAM_MB}M" > /sys/block/zram0/disksize 2>/dev/null || true; }
    mkswap /dev/zram0 2>/dev/null && swapon /dev/zram0 && info "zram swap 已启用 (${ZRAM_MB}M)" \
      || warn "zram 启用失败, 继续安装"
  else
    warn "zram 模块加载失败, 继续安装"
  fi
fi

# ---- 低内存构建并发限制: 削内存峰值 (仅 MEM < 8G 生效) ----
# 并发 cc1 内存峰值随核数线性叠加, 低内存机的峰值就是瓶颈 —— 限到 2 任务。
# 用环境变量注入 NIX_CONFIG, 对 retry 包裹的预热构建/nixos-install 全部子
# 进程生效, 无需改调用点; 大内存机 (≥8G) 不注入, 路径与默认完全一致。
# 调用者可用调用时 NIX_CONFIG 覆盖 (本块追加在后, 后者优先)。
if [ "$MEM_MB" -lt 8192 ]; then
  export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}max-jobs = 2"
  info "低内存: 限制 nix 构建并发 (max-jobs=2, 削内存峰值)"
fi

# ---- tmpfs 扩容: 安全形态 (根分档 + store 层与虚拟内存联动) ----
# 根 (工作目录/临时文件): 峰值 = nix 构建 TMPDIR + 仓库 + 缓存。低内存机默认
# 50% 仅 ~1.9G 贴峰值, 补到 4G; 中高内存机默认 50% (≥4G) 已覆盖, 且大内存
# 大核机器并行构建峰值更大, 继承默认更安全 (固定小值会砍死高配机)。
# store 可写层 (/nix/.rw-store, Live 期间 nix 全部写入面): 目标按"内存 +
# 已启用 swap"分档联动 —— 上限超过虚拟内存时, 写满触发的将是 OOM 而非
# ENOSPC (纸面超配误导); swapfile 在阶段 3 才启用, 届时重算提升 (复用本函数)。
resize_store_tmpfs() {
  [ -n "${STORE_CAP_G:-}" ] || return 0
  local cur_g
  cur_g=$(df -k /nix/.rw-store 2>/dev/null | awk 'NR==2{printf "%d", $2/1024/1024}')
  [ "${cur_g:-0}" -lt "$STORE_CAP_G" ] || return 0   # 只增不减
  mount -o remount,size="${STORE_CAP_G}G" /nix/.rw-store 2>/dev/null \
    && info "store 可写层扩容至 ${STORE_CAP_G}G (与虚拟内存联动)" \
    || warn "store 可写层扩容失败 (目标 ${STORE_CAP_G}G), 大拉取期可能空间不足"
}
store_cap_by_virt() {
  # 按当前虚拟内存 (内存 + 已启用 swap) 分档: <8G→4, <16G→8, 否则 16
  local mem_g swap_g virt_g
  mem_g=$(( MEM_MB / 1024 ))
  swap_g=$(swapon --show=SIZE --bytes --noheadings 2>/dev/null \
    | awk '{s+=$1} END{printf "%d", s/1073741824}')
  swap_g=${swap_g:-0}
  virt_g=$(( mem_g + swap_g ))
  if [ "$virt_g" -lt 8 ]; then echo 4
  elif [ "$virt_g" -lt 16 ]; then echo 8
  else echo 16; fi
}

ROOT_FSTYPE=$(findmnt -no FSTYPE / 2>/dev/null || true)
if [ "$ROOT_FSTYPE" = "tmpfs" ]; then
  # 根: 分档 —— 低内存补到 4G (构建 TMPDIR 峰值 ~2G + 余量); 高内存继承默认
  if [ "$MEM_MB" -lt 8192 ]; then
    mount -o remount,size=4G / 2>/dev/null \
      && info "根 tmpfs 扩容至 4G (低内存分档)" \
      || warn "根 tmpfs 扩容失败, 构建期临时文件可能空间不足"
  else
    info "根 tmpfs 保持默认 (50% 内存, 高内存机峰值余量充足)"
  fi
  if mountpoint -q /nix/.rw-store; then
    STORE_CAP_G=$(store_cap_by_virt)
    resize_store_tmpfs
    # nr_inodes 同样按内存比例给死 (3G 内存仅 ~83k): 拉依赖时新增的 store
    # path 条目数远超它, 空间未满即报 "No space left on device" (ENOSPC 实测)。
    # inode 只是内核对象, 1M 上限内存开销可忽略
    mount -o remount,nr_inodes=1048576 /nix/.rw-store 2>/dev/null \
      && info "store 可写层 inode 扩至 1M (防 ENOSPC)" \
      || warn "store 可写层 inode 扩容失败, 大量拉取时可能报 No space left on device"
  fi
fi


# ---- GitHub token (可选): 安装期给 Live CD 的 nix 提供凭据 ----
# 优先级: 显式 GITHUB_TOKEN 环境变量 > secrets.yaml 自动解密 (重装场景) > 匿名。
# sudo 默认清空环境变量, 需 `sudo env GITHUB_TOKEN=ghp_xxx ./install.sh ...` 传入;
# 重装同机 (旧 host key 已恢复到 Live CD /etc/ssh/) 时可免手动传参 —— 脚本自动
# 派生 age 私钥解密 secrets.yaml 的 github-token; 全新安装 key 不匹配 (或网络差
# 拉不到 sops) 解密失败, 静默回退匿名, 行为与不带 token 一致。
# access-tokens 一项即可: 分支解析与 tarball 下载均带 token 头 (fetcher 有凭据时
# 统一走 api.github.com, 5000 次/h; 无凭据则回退匿名直链, 60 次/h)。
# 凭据只活在 Live CD (tmpfs, 重启即焚); 常驻凭据装好后走 secrets.yaml (sops-nix)。
if [ -z "${GITHUB_TOKEN:-}" ] && [ -f "$SCRIPT_DIR/secrets/secrets.yaml" ] \
  && [ -f /etc/ssh/ssh_host_ed25519_key ]; then
  # 整文件 sops -d + sed 提取 (sops --extract 在无 TTY 脚本环境会挂起);
  # sed 同时剥掉 YAML 双引号 (模板值带引号, 不剥则引号随 token 进 access-tokens → 401);
  # 临时 age 私钥用完即删, 泄漏面与手动传 token 等同;
  # timeout 防网络吊死卡住安装 (首次拉取 sops/ssh-to-age 在慢网络下需数分钟)
  AGE_KEY="$(mktemp)"
  trap 'rm -f "$AGE_KEY"' EXIT   # 派生私钥即焚也覆盖中断: 解密窗口内 Ctrl-C/异常退出同样清掉
  chmod 600 "$AGE_KEY"
  info "尝试从 secrets.yaml 解密 GitHub token (host key, 超时 10 分钟)..."
  if ! GITHUB_TOKEN="$(timeout 600 nix --extra-experimental-features "nix-command flakes" \
      shell nixpkgs#sops nixpkgs#ssh-to-age -c sh -c "
      ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > '$AGE_KEY' 2>/dev/null
      cd /tmp && SOPS_AGE_KEY_FILE='$AGE_KEY' sops -d '$SCRIPT_DIR/secrets/secrets.yaml' 2>/dev/null
    " 2>/dev/null | sed -n 's/^github-token:[[:space:]]*//p' | tr -d '"' | head -1)"; then
    # 双通道回退: fresh Live CD 的 nix 首拉可能撞 mihomo 未稳窗口, 损坏 tarball
    # 且被 fetcher 缓存/store 毒化 (实测解密/disko 同因 "flake.nix does not
    # exist" 死循环) —— curl 直下 release 二进制 (走代理, --retry) 绕开 nix
    # fetcher, 打破 "解密需工具, 工具需网络" 的死循环
    info "nix shell 通道未命中, 回退 curl 直下 sops/ssh-to-age 二进制..."
    GITHUB_TOKEN=""
    case "$(uname -m)" in aarch64) REL_ARCH=arm64 ;; *) REL_ARCH=amd64 ;; esac
    if mkdir -p /tmp/decrypt-bin \
      && curl -fsSL --retry 3 --retry-delay 3 --max-time 120 \
           -o /tmp/decrypt-bin/ssh-to-age "https://github.com/Mic92/ssh-to-age/releases/download/v1.3.0/ssh-to-age.linux-$REL_ARCH" \
      && curl -fsSL --retry 3 --retry-delay 3 --max-time 180 \
           -o /tmp/decrypt-bin/sops "https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.$REL_ARCH" \
      && chmod +x /tmp/decrypt-bin/ssh-to-age /tmp/decrypt-bin/sops \
      && ! GITHUB_TOKEN="$(
        /tmp/decrypt-bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$AGE_KEY" 2>/dev/null
        cd /tmp && SOPS_AGE_KEY_FILE="$AGE_KEY" /tmp/decrypt-bin/sops -d "$SCRIPT_DIR/secrets/secrets.yaml" 2>/dev/null \
          | sed -n 's/^github-token:[[:space:]]*//p' | tr -d '"' | head -1
      )"; then
      GITHUB_TOKEN=""
    fi
  fi
  if [ -n "$GITHUB_TOKEN" ]; then
    info "GitHub token 已从 secrets.yaml 解密 (host key 匹配)"
  else
    GITHUB_TOKEN=""
    info "secrets.yaml 解密未命中 (全新安装/key 不匹配/拉取超时), 匿名拉取"
  fi
  rm -f "$AGE_KEY"
  trap - EXIT   # 私钥已清, 解除 trap 让位后续阶段 (disko 临时文件)
fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
  # 追加而非覆盖, 保留调用者已有的 NIX_CONFIG; 作用于脚本内全部 nix 调用
  NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}access-tokens = github.com=$GITHUB_TOKEN"
  export NIX_CONFIG
  unset GITHUB_TOKEN   # 子进程统一经 NIX_CONFIG 获取, 避免多渠道泄漏
  info "GitHub token 已启用 (access-tokens)"
fi

# ============================================================================
# 阶段 2: disko 分区 & 格式化 & 挂载
# ============================================================================
info "[2/4] 分区: disko 格式化 $DISK 并挂载到 /mnt"

# ---- 清理残留挂载/swap (幂等: 反复执行/上轮中断后无残留即可直接跑) ----
# 只关磁盘 swap, 保留阶段 1 创建的 zram (内存 <8G 防编译 OOM) —— 逐个 swapoff
# 而不用 swapoff -a 兜底: 那会把 zram 一并关掉, 丢掉低内存机的 OOM 防线。
# swapfile 持有 btrfs 挂载引用: 残留 swapfile 未关 → umount 失败 → disko
# 报 "is mounted" (136 实测)。故先全量 swapoff 磁盘 swap, 再 umount 两遍
# (第一遍收 root, 第二遍确认干净; 失败仍继续, disko 的 wipefs 兜底)。
for sw in $(swapon --show=NAME --noheadings 2>/dev/null | grep -v -E '^/dev/zram'); do
  swapoff "$sw" 2>/dev/null || true
done
umount -R /mnt 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
# 残留 swapfile 挂载的兜底: 若 swapoff 时 btrfs 引用未释放干净, 再试一轮
[ -f /mnt/swap/swapfile ] && swapoff /mnt/swap/swapfile 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
# 用实际设备路径替换 disks.nix 中的占位符
DISKO_CFG="$SCRIPT_DIR/hosts/${HOST_DIR}/disks.nix"
if ! grep -q 'DISK_DEVICE_PLACEHOLDER' "$DISKO_CFG"; then
  die "disks.nix 缺少 DISK_DEVICE_PLACEHOLDER 占位符, 请检查配置"
fi
# swapfile 大小与硬件配置: 调用适配脚本 (检测当前机 → 重写 disks.nix swapfile
# size + 生成 hardware-configuration.nix, 写入工作区构建后还原)。必须在 disko 之前:
# disko 分区时即读取 disks.nix 的 swapfile 大小。adapt 检测基于当前运行系统
# (Live CD 跑在目标机硬件上), 不依赖 /mnt 挂载状态。
# ADAPT_SKIP_RESUME=1: 跳过 resume_offset 探测 —— disko 前新盘未格式化 (root
# 也探不到), 重装同机时旧盘 label 的值是即将失效的 stale 值; 真实值由下方
# disko 之后对 /mnt/swap/swapfile 补探注入。
ADAPT_SKIP_RESUME=1 bash "$SCRIPT_DIR/scripts/adapt-hardware.sh" || die "硬件适配失败"

# tmpfs 完整性自愈: 低内存 Live CD 实测文件内容会被静默清零 (shmem 页随 swap
# 重建丢失), 三个适配相关文件任一为空则从 git 恢复 (boot.nix 恢复占位版,
# resume_offset 由下方 disko 后补探重新注入); 恢复不了才失败
for f in "$DISKO_CFG" "hosts/${HOST_DIR}/hardware-configuration.nix" modules/nixos/boot.nix; do
  if [ ! -s "$f" ]; then
    warn "$f 内容丢失 (tmpfs 页丢失?), 尝试从 git 恢复"
    git checkout -- "$f" 2>/dev/null || true
    [ -s "$f" ] || die "$f 为空且 git 恢复失败, 无法继续 —— 请重新获取仓库"
    info "$f 已从 git 恢复"
  fi
done
# 在临时副本中替换设备占位符, 确保原文件不受影响 (swapfile size 已由 adapt 写回原文件)
DISKO_TMP="$(mktemp -t disko.XXXXXX.nix)"
trap 'rm -f "$DISKO_TMP"' EXIT   # die/Ctrl-C 中断不把临时 .nix 留在 tmpfs /tmp
sed "s|DISK_DEVICE_PLACEHOLDER|$REAL_DISK|g" "$DISKO_CFG" > "$DISKO_TMP"

# 低内存安装期 swapfile 宽松化 (仅 MEM < 8G; 仅此副本, 原 disks.nix 不受影响):
# 与内存等大时 3.8G 机仅 4G 磁盘 swap, 虚拟总 ~10G 偏紧, 构建峰值期换页
# 带宽不足会拖到"看似卡死" (3.8G VM 历史症状) —— 放宽到 8G 留足虚拟空间。
# disko 按此副本创建 → 安装期定大小即"终身"; 稳态由 adapt 维持"与内存
# 等大"语义 (休眠只需 swap ≥ RAM, 无谓占用目标盘), 与装机后语义一致。
if [ "$MEM_MB" -lt 8192 ] && grep -q 'swap\.swapfile\.size' "$DISKO_TMP"; then
  sed_replace "s|swap\.swapfile\.size = \"[^\"]*\"|swap.swapfile.size = \"8G\"|" "$DISKO_TMP"
  info "低内存安装期: swapfile 放宽至 8G (虚拟内存留足)"
fi
# disko --mode zap_create_mount: 等效 destroy + format + mount, 一步完成
# 不提供 --yes-wipe-all-disks: 全盘 wipe 必须经上方人工确认 (及 disko 自身
# 对已分区盘的交互检查), 无人值守场景请先人工清盘或预分区。
DISKO_FLAGS=(--mode zap_create_mount)
# --root-mountpoint 指向 /mnt (disko 在该路径下执行挂载)
# 用 flake 锁定的 disko 包 (flake.nix 导出 inputs.disko): 避免拉 master 触发
# GitHub API 匿名限流 403 (已修复过的回归), 且与 nixos-install 构建用的锁定版本一致。
# 输出捕获到日志 (失败后按特征分类提示用); 日志只建一份, 每轮覆盖 ——
# 重试不再另开新文件 (旧实现首轮日志泄漏在 tmpfs /tmp), 调用方负责 rm
DISKO_LOG="$(mktemp -t disko-log.XXXXXX)"
disko_run() {
  nix --extra-experimental-features "nix-command flakes" \
    run "$SCRIPT_DIR#disko" -- "${DISKO_FLAGS[@]}" --root-mountpoint /mnt "$DISKO_TMP" 2>&1 | tee "$DISKO_LOG"
  return "${PIPESTATUS[0]}"
}

# 首次失败不立即 die: 分类提示后强制清理重跑一次 (幂等: disko 本身支持
# 重入, 分区是 zap_create_mount 语义); 重跑仍失败才 die。
# 分类依据错误特征如实区分 —— 曾一律提示"磁盘被占用 reboot", 实际是节点
# 不稳的 SSL eof (实测踩坑), 误导排障方向。
if ! disko_run; then
  if grep -qiE "No space left on device" "$DISKO_LOG"; then
    warn "disko 失败: store 空间不足 (容量/inode) —— inode 已扩容, 重试通常通过"
  elif grep -qiE "could not download|unable to download|SSL|TLS|timed out|timeout|connection (reset|refused)|failed to fetch|HTTP error|curl \(|flake\.nix' does not exist|narHash" "$DISKO_LOG"; then
    warn "disko 失败疑似网络异常 (节点不稳/拉取中断/tarball 损坏, 见上方日志)"
    if [ "${export_use_mihomo:-}" = 1 ]; then
      warn "  处理: 面板 http://${LAN_IP:-127.0.0.1}:9090/ui 切换节点后重试, 或直接重跑本脚本"
    else
      warn "  处理: 检查网络连通性后重试, 或直接重跑本脚本"
    fi
    warn "  自检: curl -m 10 -s -x http://127.0.0.1:7890 -o /dev/null -w '%{http_code}' https://cache.nixos.org/nix-cache-info"
    # fetcher 缓存毒化自愈: 坏 tarball 元数据被缓存后, 命中缓存的重试永不自愈
    rm -f /root/.cache/nix/fetcher-cache-v4.sqlite
  else
    warn "disko 失败疑似磁盘/挂载问题 (残留占用等, 见上方日志)"
  fi
  warn "  尝试强制清理残留后重试一次..."
  swapoff /mnt/swap/swapfile 2>/dev/null || true
  umount -R /mnt 2>/dev/null || true
  umount -R /mnt 2>/dev/null || true
  if ! disko_run; then
    rm -f "$DISKO_LOG"
    die "安装中止。请按上方分类处理 (网络→切节点重试; 磁盘→reboot 后重跑)。"
  fi
fi
rm -f "$DISKO_LOG"

mountpoint -q /mnt     || die "挂载失败: /mnt"
# 独立 nix 子卷是本仓库 disks.nix 布局, 其他布局 (单根子卷) 下仅警告不阻断
# (swapfile 同样走 warn 风格, 保持一致性)
mountpoint -q /mnt/nix || warn "未检测到 /mnt/nix 独立挂载 (若 disks.nix 无独立 nix 子卷属预期)"
info "磁盘已分区并挂载到 /mnt (disko)"

rm -f "$DISKO_TMP"

# ---- resume_offset 补探: disko 刚重建的新 swapfile 才有首装系统的真实偏移 ----
# 内核唤醒侧只认 cmdline 的 resume_offset= (断电冷启动时运行时写入已丢失),
# 首装系统必须带正确值, 否则休眠唤醒失败 (hibernate-now 只能告警, 修不了 cmdline)。
# 此刻 @swap 已由 disko 挂载到 /mnt/swap, root 直读, 无需再挂载。
if [ -f /mnt/swap/swapfile ]; then
  NEW_OFFSET="$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile 2>/dev/null || true)"
  if [ -n "$NEW_OFFSET" ] && inject_resume_offset "$NEW_OFFSET"; then
    info "resume_offset=$NEW_OFFSET 已注入 boot.nix (disko 后补探, 首装真实值)"
  else
    warn "resume_offset 探测/注入失败, boot.nix 保持占位值 —— 首启后 rebuild 一次修正"
  fi
else
  warn "未找到 /mnt/swap/swapfile, 跳过 resume_offset 补探 (首启后 rebuild 修正)"
fi

# ============================================================================
# 阶段 2.5: git 验证 (防呆: 确认硬件配置已被 git 跟踪)
# ============================================================================
# nix path fetcher (--flake /abs/path) 直接读工作区, 不依赖 index; 此处检查
# 仅作防护: hardware-configuration.nix 必须是 tracked 文件 (仓库模板自带),
# 若缺失说明适配未生成或仓库不完整。
if [ ! -d "$SCRIPT_DIR/.git" ]; then
  die "$SCRIPT_DIR/.git 不存在, 无法继续。请从 git clone 重新获取本仓库。"
fi
if ! git -C "$SCRIPT_DIR" ls-files --error-unmatch hosts/${HOST_DIR}/hardware-configuration.nix >/dev/null 2>&1; then
  die "hardware-configuration.nix 未被 git 跟踪, 无法继续安装"
fi
info "硬件配置就绪, nixos-install 将从工作区读取"

# ============================================================================
# 阶段 3: 启用 swap
# ============================================================================
info "[3/4] 启用 swap"
SWAPFILE="/mnt/swap/swapfile"
if [ -f "$SWAPFILE" ]; then
  # 已在内核的 swapfile 重复 swapon 会报 "read swap header failed"/"Device or
  # resource busy" (重跑安装 / 上轮中断后 swapoff 没跑到的残留) —— 先查再挂,
  # 残留 swap 指向的是本轮 disko 前 mkswap 过的旧镜像, 内容已废, 必须先关
  if swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$SWAPFILE"; then
    warn "swapfile 已在内核 (上轮安装残留), swapoff 后按新镜像重新挂载"
    swapoff "$SWAPFILE" 2>/dev/null || true
  fi
  mkswap "$SWAPFILE" >/dev/null 2>&1 && info "swapfile 已重新 mkswap (disko 新建, 保险刷头)" || warn "mkswap 失败, 沿用 disko 生成的镜像"
  swapon "$SWAPFILE" && info "磁盘 swapfile 已启用" || warn "swapfile 启用失败, 继续安装"
else
  warn "swapfile 不存在 ($SWAPFILE), disko 可能未创建, 继续安装"
fi
info "总 swap: $(free -m | awk '/Swap:/{print $2}')M"

# swapfile 启用后虚拟内存扩大, 重算 store 可写层上限并提升 (阶段 1 无磁盘
# swap 时算出的值偏保守; 只增不减, 见 resize_store_tmpfs)
if mountpoint -q /nix/.rw-store; then
  STORE_CAP_G=$(store_cap_by_virt)
  resize_store_tmpfs
fi

# ============================================================================
# 阶段 4: nixos-install
# ============================================================================
info "[4/4] nixos-install: 安装 NixOS (请耐心等待)"
# 设置 GOPROXY 使用国内镜像, 避免 proxy.golang.org 超时导致 sops-install-secrets 编译失败
export GOPROXY="https://goproxy.cn,direct"

# nixos-install 默认会生成 /mnt/etc/nixos/configuration.nix 模板文件
# 该文件干扰后续 nixos-rebuild switch (flake 优先读取 /etc/nixos)
# 将其删除, 确保系统只使用 flake 配置
rm -f /mnt/etc/nixos/configuration.nix 2>/dev/null || true
rm -f /mnt/etc/NIXOS 2>/dev/null || true

# ---- host key 固化: nixos-install 前放入 chroot (secrets 解密一致性) ----
# nixos-install 的 activation 阶段 sops-install-secrets 即需读取 chroot 的
# /etc/ssh/ssh_host_ed25519_key 派生 age 密钥解密 secrets (secrets.nix 的
# sops.age.sshKeyPaths)。全新格式化的盘上此刻尚无 host key, 不提前放入则
# 安装期解密必失败 (Cannot read ssh key / 0 successful groups); 固化后的
# key 在首启时被 sshd 复用, 与 secrets 加密公钥保持一致。
# 重装/换盘场景: 先在 Live CD 上恢复旧 host key 到 /etc/ssh/ 再运行本脚本。
if [ -f /etc/ssh/ssh_host_ed25519_key ]; then
  info "固化 SSH host key 到目标系统 (secrets 解密一致性)"
  mkdir -p /mnt/etc/ssh
  cp -a /etc/ssh/ssh_host_ed25519_key* /mnt/etc/ssh/ 2>/dev/null \
    || warn "host key 复制失败, 新系统将重新生成 (需重启后重新初始化 secrets)"
  # rsa key 一并固化 (若存在), 消除 sops-install-secrets 扫描 rsa 的噪音警告
  cp -a /etc/ssh/ssh_host_rsa_key* /mnt/etc/ssh/ 2>/dev/null || true
else
  warn "Live CD 无 /etc/ssh/ssh_host_ed25519_key (重装/换盘应先恢复旧 key)"
  warn "安装期 sops 解密将失败; 重启后需按 README 初始化 secrets (host key 公钥 + 模板)"
fi

# 最终防线: 任何 0 字节 .nix 都会让 nixos-install 以晦涩语法错失败 (tmpfs
# 内容丢失实测); 这里统一拦截并给出恢复指引。
# 注意 || true: set -euo pipefail 下 find 无匹配 → grep 无输入 rc=1 → 命令
# 替换 rc=1 → 整行赋值失败静默退出 (仓库无空文件时必触发, 实测踩坑)。
EMPTY_NIX=$(find "$SCRIPT_DIR" -name "*.nix" -size 0 2>/dev/null | grep -v result | head -3 || true)
if [ -n "$EMPTY_NIX" ]; then
  echo "$EMPTY_NIX" | while read -r f; do
    git checkout -- "${f#"$SCRIPT_DIR/"}" 2>/dev/null || true
  done
  EMPTY_NIX=$(find "$SCRIPT_DIR" -name "*.nix" -size 0 2>/dev/null | head -3 || true)
  [ -z "$EMPTY_NIX" ] || die "以下 .nix 为空且 git 恢复失败, 无法继续:
$EMPTY_NIX"
  info "检测到空 .nix 文件, 已全部从 git 恢复"
fi

# (systemd-oomd 已在脚本最前统一停用, 此处不再重复处理)

# ---- store 存量搬运 (3.8G VM 实战产出) ----
# Live CD 的 store 是 overlay (tmpfs 上层), 失败重装轮的下载/构建产物会把
# 8G tmpfs 填满 (实测 100%) —— 后续任何写入 ENOSPC。disko 后先把上层存量
# store path 批量 copy 进目标盘 chroot store, 确认落盘才删源释放 tmpfs;
# 搬过去的下方预热构建直接命中, 一石二鸟。
# 注意 chroot store 的 root 是系统根 (/mnt), 不是 nix 根 —— 写成
# local?root=/mnt/nix 会错位到 /mnt/nix/nix/store, nixos-install 看不到
# (nixos-install 官方内部即 local?root=$mountPoint)。
NIX_CONN="local?root=/mnt"
store_drain() {
  local SRC_LIST DST_LIST MOVE_LIST before p
  SRC_LIST=$(find /nix/.rw-store/store -mindepth 1 -maxdepth 1 ! -type c \
    -printf '/nix/store/%f\n' 2>/dev/null | sort -u) || SRC_LIST=""
  [ -n "$SRC_LIST" ] || return 0
  DST_LIST=$(find /mnt/nix/store -mindepth 1 -maxdepth 1 ! -type c \
    -printf '/nix/store/%f\n' 2>/dev/null | sort -u) || DST_LIST=""
  MOVE_LIST=$(comm -23 <(printf '%s\n' "$SRC_LIST") <(printf '%s\n' "$DST_LIST") 2>/dev/null) || MOVE_LIST=""
  [ -n "$MOVE_LIST" ] || return 0
  before=$(df -k /nix/.rw-store 2>/dev/null | tail -1 | awk '{print $3}')
  info "搬运 $(printf '%s\n' "$MOVE_LIST" | wc -l) 个存量 store path 到目标盘 (腾出 tmpfs)..."
  # 批量分传 (每批 1000: 防 ARG_MAX, 分批使失败只波及单批); 尽力而为 —— 失败
  # 静默 (只损失增量命中), 缺失项由预热构建在目标盘重新下载
  printf '%s\n' "$MOVE_LIST" \
    | xargs -r -n 1000 nix --extra-experimental-features "nix-command flakes" \
        copy --to "$NIX_CONN" >/dev/null 2>&1 || true
  # 只删确实落盘的 (copy 失败/跳过的保留); overlay whiteout (-type c) 天然不碰
  comm -12 <(printf '%s\n' "$SRC_LIST") \
    <(find /mnt/nix/store -mindepth 1 -maxdepth 1 ! -type c \
      -printf '/nix/store/%f\n' 2>/dev/null | sort -u) 2>/dev/null \
    | while read -r p; do rm -rf "/nix/.rw-store/store/${p##*/}"; done
  info "存量搬运完成, 释放 tmpfs $(df -k /nix/.rw-store 2>/dev/null | tail -1 \
    | awk -v b="${before:-0}" '{d=(b-$3)/1024/1024; if(d<0)d=0; printf "%.1fG", d}')"
  return 0
}
# .rw-store 容量已由阶段 1 (store_cap_by_virt 联动) + 阶段 3 (swapfile 启用后
# 重算提升) 接管; 此处不再固定补扩 16G —— 避免覆盖联动值 (纸面超配会让写满
# 触发 OOM 而非 ENOSPC, 见上方安全形态注释)。
# 无待搬运时完全静默 (占用前后无变化的两行纯噪音)。
store_drain

# ---- 预热构建: 低内存 VM 内存峰值分离 (nixos-install 段前置) ----
# nixos-install 单进程同时扛 求值+编译+复制, 3G 内存 VM 实测在求值早期静默
# 死亡 (nix daemon 被内存压死, 无 OOM 记录, 进程消失无输出)。先把系统闭包
# 独立构建出来 (--store chroot: 与 nixos-install 官方机制一致, 产物直落
# 目标盘 btrfs, Live CD tmpfs 零膨胀; --no-link, dst store 增量保留):
#   - 成功: nixos-install 只需快速求值 (闭包已在 store) + 增量复制 + 引导,
#     峰值大降, 三种阶段不再叠加;
#   - 失败: 有输出有 rc, 静默死亡点前置为可见错误; 重试时 store 增量保留,
#     通常更快。
# 与 nixos-install 段同用通用 retry (次数/间隔见顶部 RETRY_N/RETRY_WAIT_S)。
# 前置: mihomo/环境变量/GOPROXY 已就位, 拉取走 TUN/代理。
# 与 nixos-install 段同用 retry: 增量语义 (dst store 闭包保留, 重试只补差量)。
# 成功即闭包入目标盘 store (--print-out-paths 输出即真实路径, 直接可见)。
if retry "预构建系统闭包" nix --extra-experimental-features "nix-command flakes" \
    build --store "$NIX_CONN" \
    ".#nixosConfigurations.${HOST_NAME}.config.system.build.toplevel" \
    --no-link --print-out-paths; then
  info "系统闭包预构建完成, nixos-install 转增量复制 (内存峰值已分离)"
else
  die "系统闭包 $RETRY_N 次构建失败 (低内存环境: 建议增大 VM 内存, 或查看上方错误)"
fi

# nixos-install: 经上方预热构建, 本段以快速求值 + store 增量复制 + 引导装写
# 为主 (编译峰值已前置到可观测的预热步骤)。历史上 3G 内存 VM 的静默死亡点
# 已被预热构建接管, 但复制阶段 daemon 仍可能被内存压死, 保留两道防线:
#   a) 完成标志校验 (下方): 静默死亡立即暴露, 不再误判为成功/卡死;
#   b) 重试包装 (retry): daemon 被杀会留下已复制的 store 内容,
#      重跑增量复制, 第二次通常只需补差量 (RETRY_N 非零时封顶, 默认无限)。
# 前置: mihomo/环境变量已就位, nixos-install 的拉取走 TUN/代理。
# nixos-install 内部即 --store local?root=/mnt 构建 (官方机制), 预热产物直接
# 命中, 无需 store 复制腾挪。
#
# 单次尝试 + 完成标志甄别: rc!=0 但 system 已生成 => 实际成功 (后半段小失败)。
# 甄别: 语法/求值错误重试无意义, 直接失败; daemon 挂/断连/网络类才值得重试。
# profile 是 chroot 绝对 symlink (断链语义, 见下方强校验注释), 用 readlink 判。
nixos_install_once() {
  if nixos-install --flake ".#${HOST_NAME}" --no-channel-copy --no-root-password; then
    return 0
  fi
  if [ -e /mnt/etc/NIXOS ] || [ -n "$(readlink /mnt/nix/var/nix/profiles/system 2>/dev/null)" ]; then
    warn "nixos-install 退出码非 0, 但完成标志已生成 —— 视作安装成功"
    return 0
  fi
  return 1
}
if ! retry "nixos-install" nixos_install_once; then
  die "nixos-install $RETRY_N 次尝试均失败 (详见上方输出)"
fi

# ---- nixos-install 成功标志强校验 ----
# 静默死亡 (daemon 被杀) 的 historical 形态: 无输出退出但 rc=0 的管道吞掉过。
# 没有这几个标志就不能算装完。
# 注意: system profile 是 chroot 内的绝对 symlink (system -> system-N-link ->
# /nix/store/...), 宿主 (Live CD) 视角必然断链 —— [ -e ] 会对装好的系统误判
# 失败 (首次安装实测踩坑)。以 readlink 解析 generation 再按 chroot 根实测。
[ -e /mnt/etc/NIXOS ] || die "/mnt/etc/NIXOS 不存在 —— 目标系统未初始化"
SYSTEM_GEN=$(readlink /mnt/nix/var/nix/profiles/system 2>/dev/null || true)
[ -n "$SYSTEM_GEN" ] || die "/mnt/nix/var/nix/profiles/system 不存在 —— 系统闭包未生成"
SYSTEM_PATH=$(readlink "/mnt/nix/var/nix/profiles/${SYSTEM_GEN##*/}" 2>/dev/null || true)
[ -d "/mnt/nix/store/${SYSTEM_PATH##*/}" ] \
  || die "system generation 目标 (${SYSTEM_PATH:-未知}) 不在 /mnt/nix/store —— 系统闭包未生成"
[ -s /mnt/boot/grub/grub.cfg ] || warn "grub.cfg 缺失 (bootloader 阶段可能未完成), 首启可能无法引导"
STORE_N=$(ls /mnt/nix/store 2>/dev/null | wc -l)
[ "$STORE_N" -gt 100 ] || die "store 仅 $STORE_N 条, 安装未真正完成"
info "nixos-install 完成标志校验通过 (store=$STORE_N 条)"

# ---- 仓库就位: 复制到目标系统家目录 (日常使用无需再 clone) ----
# 解析 mainUser (local.nix, 兼容 mkForce 两种写法)。解析失败直接 die ——
# 兜底 "user" 会把仓库静默装到错误家目录, 比失败更难排查。
MAIN_USER="$(grep -oP 'mainUser[[:space:]]*=[[:space:]]*(lib\.mkForce[[:space:]]*)?"\K[^"]+' \
  hosts/${HOST_DIR}/local.nix 2>/dev/null | head -1 || true)"
[ -n "$MAIN_USER" ] || die "无法从 hosts/${HOST_DIR}/local.nix 解析 mainUser, 拒绝继续"
# 前缀必须带 /mnt: persist 子卷经 disko 挂在 /mnt/persist, 裸 /persist 是
# Live CD 自己的 tmpfs —— 写进去重启即焚, cp/chown/完成提示却照常"成功"
# (首装实测: 装完 ~/code/nixos-config 凭空消失, 2302cea 引入即坏)
mountpoint -q /mnt/persist || die "persist 子卷未挂载 (/mnt/persist), 仓库无法就位"
DEST="/mnt/persist/home/${MAIN_USER}/code/nixos-config"
if [ -d "$DEST/.git" ]; then
  # 重装场景: 目标已有仓库 (可能含用户未 push 的改动), 绝不覆盖
  warn "目标仓库已存在 ($DEST), 保留现有内容未覆盖"
elif [ -e "$DEST" ]; then
  # 中断残留 (如上次 cp -a 半途而死, 缺 .git): 直接 cp 会嵌套成
  # nixos-config/nixos-config 且完成提示指向外层空目录 —— 拒绝并交人工
  die "$DEST 已存在但缺 .git (疑似上次安装中断残留), 请手工清理后重跑"
else
  mkdir -p "$(dirname "$DEST")"
  cp -a "$SCRIPT_DIR" "$DEST" || die "仓库复制失败 ($DEST), 请检查目标盘空间"
  # 复制完整性校验: 源在 tmpfs, 低内存下文件内容可能已被清零 (本会话实测),
  # cp 会连损坏内容一起复制 —— 大小不符的文件提示重启后 git 恢复
  for f in flake.nix flake.lock hosts/default/disks.nix \
           hosts/default/hardware-configuration.nix modules/nixos/boot.nix; do
    SRC_S=$(stat -c %s "$SCRIPT_DIR/$f" 2>/dev/null || echo 0)
    DST_S=$(stat -c %s "$DEST/$f" 2>/dev/null || echo 0)
    if [ "$SRC_S" != "$DST_S" ] || [ "$DST_S" = 0 ]; then
      warn "仓库文件 $f 大小异常 (源=$SRC_S 目标=$DST_S)"
      warn "  重启进新系统后修复: cd ~/code/nixos-config && git checkout -- ."
    fi
  done
  # 属主给目标用户 (uid/gid 从装好系统的 /mnt/etc/passwd 查询)
  U_ID="$(grep "^${MAIN_USER}:" /mnt/etc/passwd 2>/dev/null | cut -d: -f3 || true)"
  G_ID="$(grep "^${MAIN_USER}:" /mnt/etc/passwd 2>/dev/null | cut -d: -f4 || true)"
  if [ -n "$U_ID" ]; then
    chown -R "${U_ID}:${G_ID:-$U_ID}" "/mnt/persist/home/${MAIN_USER}/code"
    info "仓库已就位: $DEST (属主 ${MAIN_USER})"
  else
    warn "未能确定 ${MAIN_USER} 的 uid, 仓库复制在 $DEST (属主 root, 首启后手动 chown)"
  fi
fi

# 安装完成, 还原适配产生的配置改动 (系统已固化, 仓库保持分发模板语义)
restore_adapt
info "硬件适配文件已还原 (安装已完成, 仓库保持干净)"

swapoff "$SWAPFILE" 2>/dev/null || true
swapoff /dev/zram0 2>/dev/null || true

echo ""; info "安装完成!"; echo ""
if [ -f /mnt/etc/ssh/ssh_host_ed25519_key ]; then
  echo "> SSH host key 已固化到目标系统, 安装期 secrets 解密应已成功。"
else
  echo "> SSH host key 未固化 (Live CD 上无 host key), 安装期 sops 解密已失败。"
  echo "   重启后需按 README 初始化 secrets (host key 公钥 + secrets 模板) 再 rebuild。"
fi
echo ""
echo "下一步:"
echo "  reboot"
echo ""
echo "重启后: 仓库已自动就位于 ~/code/nixos-config (无需 clone),"
echo "  确认 /run/secrets 正常解密后: cd ~/code/nixos-config && ./build.sh"
