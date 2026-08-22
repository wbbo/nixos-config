# 登录管理:greetd 直接拉起 niri-session(免显示管理器)
#
# NOTE: niri-session 内部 `systemctl --user import-environment` 未传参数,
# systemd 260+ 输出弃用警告。非致命, 无需在 greetd 层修复。
{ pkgs, config, ... }:
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
        user = config.mainUser;
      };
    };
  };

  # 排序说明: HM 模块自带 before=systemd-user-sessions, NixOS greetd 模块自带
  # after=systemd-user-sessions, 传递序天然保证 greetd 晚于 home-manager 激活
  # (首次 boot 空家目录时 niri 不会抢在 symlink 建立前生成默认配置);
  # 不加显式 after/wants: 手工拼 "home-manager-<user>.service" 在用户名含 '-'
  # 时与 HM 的 escapeSystemdPath 命名不一致, 依赖会静默落空。

  # 防 greetd 快速重启触发 systemd rate-limit 导致隔次黑屏。
  # StartLimit* 必须在 unit 级: [Service] 段不识别 (journal 实证报
  # "Unknown key ... in section [Service], ignoring"), 放 serviceConfig 从未生效。
  systemd.services.greetd = {
    startLimitBurst = 20;
    startLimitIntervalSec = 30;
    # mixed: 主进程先 TERM (systemd 默认信号, 无需显式 KillSignal) + 剩余进程 KILL, 清理 niri-session 残留
    serviceConfig.KillMode = "mixed";
  };
}
