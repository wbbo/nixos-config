# 登录管理:greetd 直接拉起 niri-session(免显示管理器)
#
# NOTE: niri-session 内部 `systemctl --user import-environment` 未传参数,
# systemd 260+ 输出弃用警告。非致命, 无需在 greetd 层修复。
{ pkgs, ... }:
{
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # 启动前先清理上一个 session 残留的 niri 进程。
        # 场景: 用户使用 nixos-rebuild test 或 systemctl restart greetd
        #       时，旧 niri 可能还未退出，niri-session 检测到冲突就会
        #       退出，greetd 陷入死循环直到 start-limit-hit。
        command = "${pkgs.bash}/bin/bash -c 'pkill -x niri 2>/dev/null; exec ${pkgs.niri}/bin/niri-session'";
        user = "wbb";
      };
    };
  };

  # 防止 greetd 快速重启触发 systemd rate-limit 导致隔次黑屏
  systemd.services.greetd.serviceConfig = {
    StartLimitBurst = 20;
    StartLimitIntervalSec = 30;
    KillMode = "mixed";
    KillSignal = "SIGTERM";
  };
}
