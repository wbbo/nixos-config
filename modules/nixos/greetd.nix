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

  # ── 图形会话语言 ──────────────────────────────────────────────────
  # ⚠ 2026-09-16 实测: 下面这条 `Environment=LANG` **对 D-Bus 激活路径无效**。
  # 保留仅为 greetd 自身进程环境的一致性, 不要再把它当作会话语言的开关。
  #
  # 为什么无效: 它只设置 greetd 自身进程的环境; greetd 经 PAM 建立用户会话时,
  # /etc/pam/environment 里的 `LANG DEFAULT="en_US.UTF-8"` 会重新设上 (DEFAULT=
  # 只在"未设置"时跳过, 而 PAM 会话的环境并非从 greetd 进程继承)。
  # 回滚本条并重启后实测: systemd --user 仍是 LANG=en_US.UTF-8。
  #
  # 真正的注入点在 modules/home/default.nix 的 `systemd.user.services.session-lang`
  # —— 必须在 niri-session 的 `import-environment` **之后**设才不被覆盖。
  # 完整的实测链路与两条失败路径见该处注释。
  #
  # 与 niri config.kdl 的 environment{} 块同值 —— 那边只覆盖 niri 自己 spawn
  # 的子进程, 是另一条路径上的双保险 (这条是有效的)。
  systemd.services.greetd.environment.LANG = "zh_CN.UTF-8";

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
