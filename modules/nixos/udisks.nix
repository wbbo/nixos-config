# 可移动介质自动挂载 (U 盘 / 外接移动硬盘)
# 架构: udisks2 为挂载引擎 (polkit 对活动会话放行可移动设备免密),
#       用户侧 udiskie 守护 (programs/udiskie.nix) 监听并自动挂载到
#       /run/media/<user>/<label>, 插拔经 Noctalia 通知。
# 只挂可移动设备: 内置盘 (HintSystem=true, 含 Windows nvme0n1p3) 不受影响。
{ ... }:
{
  services.udisks2.enable = true;
  services.gvfs.enable = true; # gio/GUI 生态的卷监控 + 回收站/手机 MTP 支持

  # 文件系统驱动: NTFS (USB 盘常见) / exFAT (大容量 U 盘常见)
  # 与 boot.nix 的 btrfs 列表自动拼接 (listOf 选项合并语义)
  boot.supportedFilesystems = [ "ntfs" "exfat" ];
}
