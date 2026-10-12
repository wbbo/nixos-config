# 时区 / 语言环境 / 控制台
{ lib, pkgs, ... }:
{
  time.timeZone = "Asia/Shanghai";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_TIME = "zh_CN.UTF-8";
      LC_MEASUREMENT = "zh_CN.UTF-8";
      LC_NUMERIC = "zh_CN.UTF-8";
      LC_PAPER = "zh_CN.UTF-8";
      LC_CTYPE = "zh_CN.UTF-8";
    };
  };

  # 分工: 本节只管**系统与 TTY** —— /etc/locale.conf → PID1 → 系统服务;
  # /etc/pam/environment → 各会话继承的默认值(均为 pam_env 的 DEFAULT=)。
  # **图形会话**的语言另由 greetd 单元注入 (modules/nixos/greetd.nix), 因为
  # niri-session 会把登录会话环境整体 import 进 systemd user manager, 而
  # D-Bus 激活的 GUI 程序继承的正是那一份 (locale.conf 在此路径上被覆盖)。

  console = {
    # 内核控制台字体 (影响所有 TTY, 含 tuigreet 登录界面)。
    # TUI 只能用 PSF 位图字体: 内核控制台没有字体渲染栈 (无 freetype/fontconfig),
    # 且每套字体受 MAX_GLYPH=512 限制 (drivers/tty/vt/consolemap.c) —— TTF/CJK
    # 都不可能, 要用系统字体只能换图形 greeter (regreet/gtkgreet)。
    # ter-v18n: Terminus "v" 系列 (512 字形 = 内核上限, 其余系列均 256),
    # 10x18 → 1080p 下 192x60 字符。
    # 档位按 **字形墨迹 (cap height)** 与 GUI 终端对齐, 而不是按字符格高 ——
    # 位图字体为低分辨率可读性几乎顶格 (cap 占格 67%), 矢量字体留白多
    # (Maple Mono: em 仅占 cell 的 70%, x-height 仅占 em 的 55%)。实测:
    #   kitty (Maple Mono 12pt, 全屏 47 行 ⇒ cell 23px): cap=11.7px, x=8.8px
    #   ter-v18n: cap=12px (67%), x=9px (50%)   ← 与上述最接近, 故取此档
    #   ter-v20n: cap=13px / ter-v22n: cap=14px (按格子高对齐的选法, 观感偏大)
    # 代价: 位图无行距留白, 同字号下一屏行数比 kitty 多 (60 行 vs 47 行)。
    # 免 rebuild 预览 (在目标 tty 上即时生效):
    #   sudo setfont -C /dev/tty2 /etc/kbd/consolefonts/ter-v18n.psf.gz
    font = "ter-v18n";
    # 供随时切回 Terminus 系列 (ter-v16n / v20n / v22n / v24n / v28n / v32n);
    # kbd 自带字体 (如 LatGrkCyr) 不依赖此处声明
    packages = [ pkgs.terminus_font ];
    keyMap = lib.mkDefault "us";
    useXkbConfig = true; # 让 TTY 复用 xkb.options
  };
}
