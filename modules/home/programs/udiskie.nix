# udiskie —— 可移动介质自动挂载守护 (udisks2 的用户侧监听)
# 插入 U 盘/移动硬盘自动挂载到 /run/media/<user>/<label>, 插拔走
# Noctalia 通知; tray=auto 依赖 Noctalia 的 tray widget ([widget.tray] drawer)。
# 注意: 该 HM 版本选项已从 programs.udiskie 迁移至 services.udiskie (守护进程类)
{ ... }:
{
  services.udiskie = {
    enable = true;
    automount = true;   # 插入即挂载 (udisks2 HintSystem=false 的可移动设备)
    notify = true;      # 挂载/卸载/拔出事件通知
    tray = "auto";      # 托盘图标 (有 StatusNotifier 宿主时显示, 可右键安全弹出)
  };
}
