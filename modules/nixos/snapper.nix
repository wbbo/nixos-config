# Snapper —— btrfs 时间线快照 (仅用户数据保护)
# 只保留 persist config: 对 @persist 做时间线快照 + 自动清理。
#
# root config 与 grub-btrfs 快照引导链已于 2026-09 彻底移除 —— 系统回滚
# 回归 NixOS generation (GRUB 的 "NixOS - All configurations" 菜单, 零额外
# 维护), 不再维护快照引导的自有链路 (reactivation 反噬/嵌套子卷等兼容面)。
#
# 快照存储: @persist 下嵌套子卷 .snapshots (路径 @persist/.snapshots; 2026-09-26
# 由独立 @snapshots 子卷迁移而来, 迁移后布局为 btrfs-assistant 等工具的标准
# 识别形态, 见 modules/nixos/btrfs-assistant.nix 头注释)。
{ config, lib, pkgs, ... }:
{
  services.snapper.configs.persist = {
    SUBVOLUME = "/persist";
    ALLOW_GROUPS = [ "wheel" ];

    # 时间线快照 (由 systemd.timer 触发)
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;

    # 保留策略
    TIMELINE_LIMIT_HOURLY = 12;
    TIMELINE_LIMIT_DAILY = 7;
    TIMELINE_LIMIT_WEEKLY = 4;
    TIMELINE_LIMIT_MONTHLY = 6;
    TIMELINE_LIMIT_YEARLY = 0;
  };
}
