# Snapper —— btrfs 自动快照
# 两份 config:
#   persist —— 对 @persist 做时间线快照 + 自动清理 (原有行为不变)。
#   root    —— 对 @root 打快照, 供 grub-btrfs 生成 GRUB 快照引导菜单。
#              TIMELINE 关闭 (根卷靠 rebuild/手动快照, 无需小时级噪声),
#              NUMBER_CLEANUP 保留最近 20 个, 滚动淘汰。
#
# 快照存储布局 (disks.nix):
#   @persist 的快照落 @snapshots (挂 /persist/.snapshots, 独立子卷);
#   @root 的快照落 @root/.snapshots (嵌套子卷, 不占快照自身)。
#
# grub-btrfs 集成见 grub-btrfs.nix: 41_snapshots-btrfs 生成器挂在
# boot.loader.grub.extraInstallCommands, 每次 rebuild 后重扫快照重建菜单。
{ config, lib, pkgs, ... }:
let
  # 开机快照 (取代 nixpkgs snapper-boot): 快照创建时把当前 system closure
  # (toplevel) 记入 userdata "nixos-init"。grub-btrfs.nix 生成快照引导条目时
  # 读 /.snapshots/N/info.xml 提取此值作 init= 内核参数 —— NixOS systemd
  # initrd 的 initrd-nixos-activation 严格要求 cmdline 有 init=, 缺失则
  # switch-root 失败 (快照引导卡死的根因); 而快照是 RO 子卷, /run
  # (tmpfs) 不进快照, 引导期无法从快照自身取 current-system, 只能在
  # 创建时埋点。userdata 语义见 grub-btrfs.nix。
  bootSnapshot = pkgs.writeShellApplication {
    name = "snapper-boot-snapshot";
    runtimeInputs = with pkgs; [
      snapper
      coreutils
    ];
    text = ''
      set -euo pipefail
      # /run/current-system 在 multi-user.target 期已指向本代系统
      SYSTEM="$(readlink -f /run/current-system)"
      if [ ! -x "$SYSTEM/init" ]; then
        echo "snapper-boot-snapshot: $SYSTEM/init not found, skip" >&2
        exit 0
      fi
      snapper --config root create \
        --cleanup-algorithm number \
        --description boot \
        --userdata "nixos-init=$SYSTEM"
    '';
  };
in
{
  services.snapper = {
    configs = {
      persist = {
        SUBVOLUME = "/persist";
        ALLOW_GROUPS = [ "wheel" ];

        # 时间线快照(由 systemd.timer 触发)
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;

        # 保留策略
        TIMELINE_LIMIT_HOURLY = 12;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 6;
        TIMELINE_LIMIT_YEARLY = 0;
      };

      root = {
        SUBVOLUME = "/";
        # wheel 可列出/创建快照 (snapper -c root list/create)
        ALLOW_GROUPS = [ "wheel" ];
        ALLOW_USERS = [ config.mainUser ];

        # 不做时间线: 根卷快照是"可引导还原点", rebuild 前手动/钩子触发
        TIMELINE_CREATE = false;

        # number 清理算法: 保留最近 N 个, 配合 snapper-boot (开机快照)
        NUMBER_CLEANUP = true;
        NUMBER_LIMIT = "20";
        NUMBER_LIMIT_IMPORTANT = "5";
      };
    };

    # 开机快照不用 nixpkgs 的 snapper-boot (ExecStart 固定, 无法带 userdata):
    # 用下方自写 snapper-boot-snapshot 服务, 创建时记入 nixos-init userdata
    snapshotRootOnBoot = false;
  };

  # 每次开机对 root 打一个 number 快照 (含 nixos-init userdata, 见 bootSnapshot)
  systemd.services.snapper-boot-snapshot = {
    description = "Snapper boot snapshot of root (with nixos-init userdata)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bootSnapshot}/bin/snapper-boot-snapshot";
    };
    requires = [ "local-fs.target" ];
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/etc/snapper/configs/root";
  };

  # .snapshots 子卷补建 (幂等):
  # - 全新安装: disko 已建 @root/.snapshots 子卷 (disks.nix),
  #   `btrfs subvolume show` 命中, 跳过
  # - 存量机器 (装机时无此子卷): 直接 btrfs subvolume create。
  #   NixOS 模块不跑 `snapper create-config` (直接写 /etc/snapper/configs),
  #   不会自动建子卷, 必须自己来; 普通目录不行 —— snapper create 会在
  #   .snapshots 下建 N/snapshot 子卷, 父目录必须是子卷。
  # - /persist/.snapshots 由 disko (@snapshots 子卷) 提供, 不在此管
  system.activationScripts.root-snapshots-dirs = lib.stringAfter [ "etc" ] ''
    if ! ${pkgs.btrfs-progs}/bin/btrfs subvolume show /.snapshots >/dev/null 2>&1; then
      rm -rf /.snapshots
      ${pkgs.btrfs-progs}/bin/btrfs subvolume create /.snapshots
    fi
    chown root:wheel /.snapshots
    chmod 750 /.snapshots
  '';
}
