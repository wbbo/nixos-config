# 登录管理: greetd + tuigreet (nixpkgs 自带, 零 GUI 依赖, 直接跑在 tty)
#
# 演进: 免密直进 niri (default_session=exec niri-session, greetd 对
# default_session 不做 PAM 验证, 等于自动登录) → noctalia-greeter (密码登录
# + Shell 外观同步, 但独立 C++ 程序观感仍与锁屏有差, 需额外 flake input,
# unstable 链无 cache) → tuigreet (nixpkgs 稳定包, TUI 极简, 免维护)。
#
# NOTE: niri-session 内部 `systemctl --user import-environment` 未传参数,
# systemd 260+ 输出弃用警告。非致命, 无需在 greetd 层修复。
{ pkgs, ... }:
{
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # --sessions 扫描 wayland-sessions (.desktop), 界面显示会话名 "niri"
        # 而非 --cmd 模式下裸露的 store 路径; F2 可切换会话
        # --remember: 记住上次成功登录的用户名; --remember-session: 记住会话
        # --time/--asterisks: 时钟显示 + 密码星号回显
        command = "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --remember --remember-session --sessions ${pkgs.niri}/share/wayland-sessions";
        user = "greeter";
      };
    };
  };

  # greeter 运行用户 (greetd default_session.user, NixOS greetd 模块不自动创建)
  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
    description = "greetd greeter";
  };
  users.groups.greeter = {};

  # 防 greetd 快速重启触发 systemd rate-limit 导致隔次黑屏。
  # StartLimit* 必须在 unit 级: [Service] 段不识别 (journal 实证报
  # "Unknown key ... in section [Service], ignoring"), 放 serviceConfig 从未生效。
  systemd.services.greetd = {
    startLimitBurst = 20;
    startLimitIntervalSec = 30;
    # mixed: 主进程先 TERM (systemd 默认信号) + 剩余进程 KILL, 清理残留进程
    serviceConfig.KillMode = "mixed";
  };
}
