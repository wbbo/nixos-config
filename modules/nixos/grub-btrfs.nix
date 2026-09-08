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
# 引导语义 = "旧根卷 + 任一现存内核": 快照恢复 / 的全部内容
# (含 /nix/store), 但 /boot 是独立 ESP 不在快照内 —— 内核从
# /boot/kernels 取, 快照时代的内核只要未被 nix gc 清出 /boot 就可选。
# /persist、/swap 独立子卷不受快照影响; 恢复后用户数据完好。
{ pkgs, ... }:
let
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
      # btrfs subvolume list -sr 输出空格分隔, 末字段为路径 (相对 /):
      # 快照子卷路径 = .snapshots/<N>/snapshot (只匹配此形态, 天然排除
      # @persist/@swap 等顶层子卷与 @snapshots 下 /persist 的快照)。
      # -s 只列快照, -r 只列只读 (snapper 快照默认 readonly)。
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
      # 快照引导: root=LABEL=nixos + rootflags=subvol=<快照路径> + init=<system>/init。
      # init= 必需: NixOS systemd initrd 的 initrd-nixos-activation 严格要求
      # cmdline 有 init= (缺失时 switch-root 失败, 表现为快照引导卡死);
      # 取自快照 userdata "nixos-init" (开机快照服务创建时埋入, 见
      # snapper.nix) + "/init" —— 快照含完整 store, 该路径在快照内有效。
      # 无 userdata 的快照 (旧 boot 快照/手动创建) 无法确定 init, 跳过。
      # 不带 resume=: 若 swap 里存有休眠镜像, resume 会把根恢复为"休眠时
      # 的根", 用户选的快照被劫持; 快照引导是修复场景, 宁可丢弃休眠镜像。
      # 带 rd.fstab=no: systemd initrd 的 fstab-generator 会把 initrd-fstab
      # (/ 条目 subvol=@root) 生成为 sysroot.mount, 与 cmdline root= 生成的
      # 同名单元冲突且后写者胜 —— 不禁掉 fstab 解析, rootflags 恒被
      # subvol=@root 覆盖, 快照引导静默失效。rd.fstab=no 下 sysroot.mount
      # 只由 cmdline 生成; /persist 等 x-initrd.mount 延后到 stage2 由
      # real fstab 挂载, 无功能损失。
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
        if [ -z "$init_closure" ] || [ ! -x "/.snapshots/$num/snapshot$init_closure/init" ]; then
          echo "grub-btrfs: skip snapshot $num (no nixos-init userdata or init missing)" >&2
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
            linux /kernels/$(basename "''${KER[$ver]}") root=/dev/disk/by-label/nixos rootflags=subvol=$snap rd.fstab=no init=$init_closure/init
            initrd /kernels/$(basename "''${INIT[$ver]}")
        }
GRUB
        done
        echo "}" >> "$NEW"
      done
      if [ "$SKIPPED" -gt 0 ]; then
        echo "grub-btrfs: $SKIPPED snapshot(s) skipped (reboot once to regenerate them with userdata)" >&2
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
}
