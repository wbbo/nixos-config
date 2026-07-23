# Snapper —— btrfs 自动快照(对 @persist 做时间线快照 + 自动清理)
# 对应 install.md 第十六阶段「Snapper 管理 @persist」。
# 快照落在 /persist/.snapshots;@swap 不纳入快照。
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
