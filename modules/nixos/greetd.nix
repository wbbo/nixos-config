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
        # --sessions 扫描 wayland-sessions (.desktop), 会话名显示 desktop 的
        # Name= ("Niri") 而非 --cmd 模式下裸露的 store 路径; F3 打开会话列表
        # (F2 是手输命令入口, 已从状态栏隐藏, 见下方环境变量)
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
  #
  # ⚠ 2026-10-13 实测: 这份环境**也到不了 tuigreet (greeter 子进程)** ——
  # greetd 拉起 greeter 时的环境只取 PAM envlist (greetd src/session/worker.rs:
  # `pam.getenvlist()` 后直接 execve, **不继承 daemon 自身进程环境**), 再被
  # /etc/pam/environment 的 `LANG DEFAULT="en_US.UTF-8"` 定为英文 → tuigreet
  # 实测 LANG=en_US.UTF-8, 界面恒英文。要给 tuigreet 传配置走下方
  # /etc/tuigreet/config.toml。
  systemd.services.greetd.environment.LANG = "zh_CN.UTF-8";

  # ── tuigreet 状态栏精简 (tuigreet 0.11 配置文件) ──────────────────
  # 配置加载优先级: defaults → /etc/tuigreet/config.toml (本文件) →
  # ~/.config/tuigreet/config.toml → TUIGREET_* 环境变量 → CLI 参数
  # (tuigreet-config/src/parser.rs:36 load_config)。
  # 提示全部隐藏 (只藏文字, 按键仍有效 —— tuigreet keyboard.rs 仅按键号分发,
  # 与可见性无关): F2 手输命令单会话主机用不上; F3 会话列表本机仅 Niri 一项;
  # F12/F4 不常用; "SESS Niri" 与 F3 列表信息重复 (列表光标反色高亮且初始即
  # 停在当前会话 —— remember-session 启动时由 lastsession-path 同步,
  # tuigreet greeter.rs:397)。
  # tuigreet 0.11.1 **无"按键切换状态栏显示"功能** (按键分支/CLI/配置三处均无
  # status 开关, 已全量核对), 故只能常隐; 提示全部隐去 (含 ESC Reset), 仅保留
  # 右侧 CAPS LOCK 功能指示 (仅大写锁定时显示)。
  # 7 个开关: show_reset / show_command / show_session / show_power /
  # show_background / show_session_status / show_caps_lock;
  # status_position = "hidden" 可整条隐藏 (tuigreet-config/src/schema.rs)。
  # 配置支持热重载 (watcher 仅在进程启动时文件已存在才启用, watcher.rs:83;
  # 本机满足) —— **已实测**: 改开关 rebuild 后运行中的 greeter (pid 未变,
  # 未重启 greetd) 状态栏即时刷新。
  environment.etc."tuigreet/config.toml".text = ''
    [layout.widgets.status_bar]
    show_reset = false
    show_command = false
    show_session = false
    show_power = false
    show_background = false
    show_session_status = false
  '';

  # ── tuigreet 按键一览 (0.11.1 源码逐分支核对; 提示已全部隐藏, 此处为唯一参考) ──
  # 主登录屏:
  #   字符 / Backspace / Delete   编辑输入框
  #   ← →                         输入框内光标左右移动
  #   ^A / ^E                     光标跳到行首 / 行尾
  #   ^U                          清空当前输入框
  #   Tab                         仅用户名框: 等同 Enter (校验并跳到密码)
  #   Enter                       提交: 用户名 → 密码 → 登录
  #   Esc                         取消进行中的认证 + 重置表单 (保留用户名)
  #   F2                          手输启动命令 (绕过 .desktop)
  #   F3                          会话列表 (本机仅 Niri 一项, 反色高亮即当前)
  #   F4                          背景动画选择
  #   F12                         电源菜单 (关机 / 重启)
  # 弹窗 / 菜单内 (F2/F3/F4/F12 打开后):
  #   ↑ ↓                         上下移动选择
  #   Enter                       确认
  #   Esc                         返回上一界面 (F2 编辑器里还会还原原命令)
  # 说明: F1 未绑定; 键位可经 [keybindings] (command/sessions/power/background
  # 填 1-12, 即换 F 键号) 重映射 —— 本机用默认。隐藏的只是提示文字, 上表按键
  # 全部照常可用 (keyboard.rs 仅按键号分发)。详细定位见 AGENTS.md 2026-10-13。

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
