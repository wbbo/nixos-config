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
  # 会话环境链的源头。niri-session 启动时会跑 `systemctl --user
  # import-environment`(无参数 = 把**整个登录会话**的环境导入 systemd user
  # manager),而 D-Bus 激活的 GUI 程序继承的正是 user manager 的环境,不是
  # 调用方(如 Firefox)的 —— 例: 从 Firefox 点"打开所在文件夹"唤起 Nautilus
  # (走 org.gnome.Nautilus.service,2026-09-16 实测其父进程 = systemd --user,
  # cgroup user@1000.service)。故: 会话环境是中文,则 D-Bus 激活路径也是中文。
  #
  # 为什么注入点在 greetd 单元而非别处:
  #   - 单元级 Environment= 优先级**高于** PID1 继承来的 /etc/locale.conf 值;
  #   - /etc/pam/environment 的条目全是 pam_env 的 DEFAULT=(仅未设置时生效),
  #     一旦此处先设了, pam_env 不会再顶掉。
  # 两条失败路径(均已实测, 勿回退):
  #   - HM `systemd.user.sessionVariables` → ~/.config/environment.d/
  #     10-home-manager.conf: 被上面那句 import-environment 用登录会话的值
  #     整体覆盖, 等于没设(2026-09-12 曾以此为修复, 09-16 证伪并移除)。
  #   - 改 `i18n.defaultLocale` 为 zh_CN: 连带 locale.conf → PID1 → 系统服务
  #     与 TTY 一起变中文, 与"系统英文 + 桌面中文"的取舍不符(见 locale.nix)。
  # 与 niri config.kdl 的 environment{} 块同值 —— 那边只覆盖 niri 自己 spawn
  # 的子进程, 是另一条路径上的双保险。
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
