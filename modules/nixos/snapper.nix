# Snapper —— btrfs 自动快照(对 @persist 做时间线快照 + 自动清理)
# 对应 install.md 第十六阶段「Snapper 管理 @persist」。
# 快照存储独立于数据卷: disks.nix 的 @snapshots 子卷挂载在
# /persist/.snapshots(路径本身是子卷挂载点, 非 @persist 内部目录),
# 快照落在独立子卷上 —— @persist 损坏/误删时快照仍可恢复。@swap 不纳入快照。
{ ... }:
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
    };
  };
}
