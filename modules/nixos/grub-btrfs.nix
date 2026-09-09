# grub-btrfs —— GRUB 菜单里的可引导 btrfs 快照
# NixOS 不用 grub-mkconfig (install-grub.pl 直接生成 grub.cfg), 上游
# Antynea/grub-btrfs 的 41_snapshots-btrfs 挂不进 NixOS 的 bootloader
# 流水线; 且其内核配对逻辑 (kversion=${k#*-}) 只认 distro 风格的
# vmlinuz-<ver>/initramfs-<ver>.img, 对 NixOS copyKernels 布局
# (/boot/kernels/<storehash>-linux-<ver>-bzImage + <hash>-initrd-linux-<ver>-initrd)
# 完全失配。故自写生成器:
#
#   scan-snapshots.sh: 枚举 snapper root config 的快照
#   (/.snapshots/N/snapshot 子卷) × /boot/kernels 里可配对的
#   kernel/initrd (按内核版本号 <ver> 配对), 生成 grub-btrfs.cfg;
#   grub.cfg 的 submenu 通过 boot.loader.grub.extraConfig 挂接
#   (extraConfig 在 menu entries 前输出, configfile 读 grub-btrfs.cfg)。
#
# 引导语义 = "旧根卷 + 任一现存内核 + 现存 store": 快照恢复 / 的全部内容
# (/etc 等), 但 @nix 是独立子卷, 快照里 /nix 恒为空 —— store 由 initrd 的
# sysroot-nix.mount 挂当前 @nix (fstab 解析, 见下方生成逻辑注释); /boot 是
# 独立 ESP 亦不在快照内, 内核从 /boot/kernels 取。/persist、/swap 独立子卷
# 不受快照影响; 恢复后用户数据完好。
{ pkgs, lib, config, ... }:
let
  # 快照条目携带与正常引导一致的内核参数, 仅滤掉 root=/resume=/
  # resume_offset= (root 由快照条目自定; 快照引导不带 resume, 防休眠镜像
  # 劫持根)。★ 关键: lsm= 必须保留 —— 缺失时内核回退默认 LSM 栈 (含
  # selinux,ipe), IPE 无策略拒绝一切 exec, dbus-broker/nscd spawn 报
  # "Operation not permitted", D-Bus 挂 → 依赖它的服务全挂 → 无法登录
  # (曾实测: 快照引导缺 lsm= 即此症状, journal 见 LSM: initializing
  # lsm=capability,landlock,yama,selinux,ipe,bpf,ima)。
  kernelParams = lib.filter
    (p: !(lib.hasPrefix "root=" p) && !(lib.hasPrefix "resume" p))
    config.boot.kernelParams;
  kernelParamsStr = lib.concatStringsSep " " kernelParams;
  scanSnapshots = pkgs.writeShellApplication {
    name = "grub-scan-btrfs-snapshots";
    runtimeInputs = with pkgs; [
      btrfs-progs
      coreutils
      gawk
      gnugrep
      gnused
    ];
    text = ''
      set -euo pipefail

      GRUB_DIR="''${1:-/boot/grub}"
      LIMIT=''${GRUB_BTRFS_LIMIT:-20}

      # ── 枚举 /boot/kernels 的 kernel+initrd, 按内核版本配对 ──
      # 命名: <storehash>-linux-<ver>-bzImage / <storehash>-initrd-linux-<ver>-initrd
      # 同版本可有多个 generation 的内核文件; 用 mtime 最新的一份配对。
      declare -A KER INIT
      for f in /boot/kernels/*-linux-*-bzImage; do
        [ -e "$f" ] || continue
        ver=$(basename "$f" | sed 's/^.*-linux-\(.*\)-bzImage$/\1/')
        # 取 mtime 较新者 (各 generation 同版本内核内容一致, 任取可用)
        if [ -z "''${KER[$ver]:-}" ] || [ "$f" -nt "''${KER[$ver]}" ]; then
          KER[$ver]="$f"
        fi
      done
      for f in /boot/kernels/*-initrd-linux-*-initrd; do
        [ -e "$f" ] || continue
        ver=$(basename "$f" | sed 's/^.*-initrd-linux-\(.*\)-initrd$/\1/')
        [ -n "''${KER[$ver]:-}" ] || continue # 没有配对内核的 initrd 跳过
        if [ -z "''${INIT[$ver]:-}" ] || [ "$f" -nt "''${INIT[$ver]}" ]; then
          INIT[$ver]="$f"
        fi
      done

      # ── 枚举 snapper root 快照 (新→旧), 取 LIMIT 个 ──
      # btrfs subvolume list -sr 输出空格分隔, 末字段为路径 (相对其父子卷的
      # 显示形式): 快照子卷路径 = .snapshots/<N>/snapshot (只匹配此形态, 天然
      # 排除 @persist/@swap 等顶层子卷与 @snapshots 下 /persist 的快照)。
      # -s 只列快照, -r 只列只读 (snapper 快照默认 readonly)。
      # ★ 挂载语义转换: subvol= 内核参数按 FS 顶层卷 (id 5) 解析路径, 实测
      #   subvol=.snapshots/N/snapshot 挂载报 ENOENT (list 显示的 path 相对
      #   父子卷, 不含 @root 前缀) —— 生成 rootflags 时必须补 @root/ 前缀
      #   (subvol=@root/.snapshots/N/snapshot 实测可挂)。
      mapfile -t SNAPS < <(
        btrfs subvolume list -sr / 2>/dev/null \
          | awk '$NF ~ /^\.snapshots\/[0-9]+\/snapshot$/ {print $NF}' \
          | sort -t/ -k2 -rn \
          | head -n "$LIMIT"
      )
      if [ ''${#SNAPS[@]} -eq 0 ]; then
        exit 0 # 无快照: 不动现有 cfg (extraConfig 的 if [ -e ] 兜底)
      fi

      # ── 生成 grub-btrfs.cfg ──
      # 快照引导: root=LABEL=nixos + rootflags=rw,subvol=<快照路径> + init=<system>/init。
      # init= 必需: NixOS systemd initrd 的 find-nixos-closure 严格要求 cmdline 有
      # init= (缺失时 "No init= parameter" 报错, switch-root 失败卡死); 取自快照
      # userdata "nixos-init" (开机快照服务创建时埋入, 见 snapper.nix) + "/init"。
      # ★ closure 在"当前 @nix"里而非快照内: @nix 是独立子卷, @root 快照里 /nix
      #   恒为空目录 —— 快照引导语义本来就是 "旧根卷配置 + 现存 store" (bootloader
      #   头注同述)。故可执行检查对当前 store 做 ([ -x "$init_closure/init" ]),
      #   闭包被 nix gc 清掉的快照跳过不生成条目。
      # 不带 resume=: 若 swap 里存有休眠镜像, resume 会把根恢复为"休眠时
      # 的根", 用户选的快照被劫持; 快照引导是修复场景, 宁可丢弃休眠镜像。
      # ★ 不带 rd.fstab=no: systemd initrd 必须解析 fstab 才会挂 /sysroot/nix
      #   (@nix) 与 /sysroot/persist —— rd.fstab=no 下 find-nixos-closure 的
      #   RequiresMountsFor=/sysroot/nix/store 无从满足, closure 不可达, 快照
      #   引导卡死 (快照无法进入系统的根因)。fstab 的 / 条目 (subvol=@root) 与
      #   cmdline root= 生成的 sysroot.mount 同名: fstab-generator 处理顺序是
      #   cmdline 先、fstab 后, 且拒绝重写已存在的单元文件 ("Failed to create
      #   unit file sysroot.mount, as it already exists") —— 快照版 sysroot.mount
      #   保住, fstab 版被拒; journal 里那条 Duplicate entry 报错属预期, 无碍。
      #   (systemd 260 实测: fstab-generator add_sysroot_mount 先于 parse_fstab,
      #   已存在单元 O_EXCL 拒写; 若未来版本改为后写者胜, 快照引导会静默回退
      #   @root —— 届时 journal 必现 Duplicate 前后条目, 可循此排查。)
      # rootflags 必须带 rw: 快照条目走 cmdline root= 路径, fstab-generator 对
      # root= 默认 ro (default_rw=false); 正常启动 (root=fstab) 的 rw 来自 fstab
      # / 条目无 ro, 快照条目没有这条兜底 —— 不加 rw 则 stage2 根只读, activation
      # 写 /var 失败。NixOS 对 root=fstab 也不自动加 rw (initrd.nix 仅 gpt-auto 加)。
      # 快照为只读子卷; 若需在快照内写入 (nixos-rebuild 修复), 先
      # `btrfs property set /.snapshots/N/snapshot ro false`。
      NEW="$GRUB_DIR/grub-btrfs.cfg.new"
      mkdir -p "$GRUB_DIR"
      : > "$NEW"
      SKIPPED=0
      for snap in "''${SNAPS[@]}"; do
        num=$(echo "$snap" | cut -d/ -f2)
        # userdata nixos-init: <userdata><key>nixos-init</key><value>...</value></userdata>
        # (info.xml 不存在的快照: sed 失败 + pipefail 会让赋值非零 → set -e 退出,
        #  故先判文件存在)
        init_closure=""
        if [ -f "/.snapshots/$num/info.xml" ]; then
          init_closure=$(sed -n '/<userdata>/,/<\/userdata>/p' "/.snapshots/$num/info.xml" 2>/dev/null \
            | awk -F'[<>]' '/<key>nixos-init<\/key>/{k=1;next} k&&/<value>/{print $3; exit}')
        fi
        # closure 存在于当前 @nix (快照内 /nix 恒空, 见上方注释), init= 直接用
        # userdata 绝对路径; 检查在当前 store 上做。
        if [ -z "$init_closure" ] || [ ! -x "$init_closure/init" ]; then
          echo "grub-btrfs: skip snapshot $num (no nixos-init userdata or closure not in store)" >&2
          SKIPPED=$((SKIPPED+1))
          continue
        fi
        date=$(awk -F'[<>]' '/<date>/{print $3; exit}' "/.snapshots/$num/info.xml" 2>/dev/null || true)
        echo "submenu 'snapshot $num  ''${date:+($date)}' {" >> "$NEW"
        for ver in "''${!KER[@]}"; do
          [ -n "''${INIT[$ver]:-}" ] || continue
          cat >> "$NEW" <<GRUB
        menuentry '$ver' --class snapshots {
            insmod all_video
            set gfxpayload=keep
            search --no-floppy --label ESP --set=root
            linux /kernels/$(basename "''${KER[$ver]}") ${kernelParamsStr} root=/dev/disk/by-label/nixos rootflags=rw,subvol=@root/$snap init=$init_closure/init
            initrd /kernels/$(basename "''${INIT[$ver]}")
        }
GRUB
        done
        echo "}" >> "$NEW"
      done
      if [ "$SKIPPED" -gt 0 ]; then
        echo "grub-btrfs: $SKIPPED snapshot(s) skipped (no userdata / closure gc'd)" >&2
      fi
      # 全部快照都被跳过时 NEW 为空: 不落地 (保留旧 cfg), 避免空菜单
      if [ -s "$NEW" ]; then
        mv "$NEW" "$GRUB_DIR/grub-btrfs.cfg"
      else
        rm -f "$NEW"
        echo "grub-btrfs: no bootable snapshots, keeping previous grub-btrfs.cfg" >&2
      fi
    '';
  };
in
{
  # 每次 rebuild (bootloader 安装) 后重扫快照重建菜单。
  # scan 需要 root (btrfs subvolume list / + 写 /boot/grub): extraInstallCommands
  # 由 install-grub.sh 在 activation 期以 root 执行, 时序满足。
  boot.loader.grub.extraInstallCommands = ''
    ${scanSnapshots}/bin/grub-scan-btrfs-snapshots /boot/grub || echo "grub-btrfs: scan failed, keeping previous grub-btrfs.cfg" >&2
  '';

  # grub.cfg 挂接 submenu (仿上游 grub-btrfs 的 configfile 片段):
  # grub 变量 ${prefix} 指向 ESP 上的 grub 目录 (/boot/grub), 找不到
  # grub-btrfs.cfg 时整个块静默跳过, 不影响正常引导。
  # 花括号形式 ${prefix} 在 Nix 字符串里需转义 \$。
  boot.loader.grub.extraConfig = ''
    if [ -e ''${prefix}/grub-btrfs.cfg ]; then
    submenu 'Btrfs snapshots' {
        configfile ''${prefix}/grub-btrfs.cfg
    }
    fi
  '';

  # 快照引导清只读 (initrd 期, 等效上游 grub-btrfs 的 read-write 条目):
  # snapper 快照子卷 ro property=true 时, 即使 mount rw 也全盘 EROFS ——
  # stage2 activation 的 /bin/sh、/usr/bin/env 原子替换 (ln+mv) 失败 →
  # ERR trap 打穿 activation → 大量服务异常 + 无法登录 (journald 也写不了 /,
  # 故此前快照引导无日志留痕)。btrfs property set 是子卷元数据操作, 对非 ro
  # 子卷 (正常引导 @root) 是无害 no-op —— 服务无条件运行, 正常引导零影响。
  # 排序: after=sysroot.mount (子卷已挂) / before=initrd.target (早于
  # initrd-nixos-activation 的 prepare-root 与 switch-root)。
  # /bin/btrfs 来自 boot.initrd.systemd.initrdBin (filesystems/btrfs.nix 因
  # btrfs 进 initrd 自动注入)。失败吞掉不阻断引导 (如非 btrfs 根)。
  boot.initrd.systemd.services.grub-btrfs-clear-ro = {
    description = "Clear btrfs read-only property on sysroot (snapshot boot support)";
    after = [ "sysroot.mount" ];
    before = [ "initrd.target" "shutdown.target" ];
    requiredBy = [ "initrd.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    # script 生成 unit-script 闭包, NixOS 自动打包进 initrd (jobScripts 机制);
    # btrfs 走 /bin (initrdBinEnv, 见上注)。
    script = ''
      /bin/btrfs property set /sysroot ro false || true
    '';
  };
}
