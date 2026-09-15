# 时区 / 语言环境 / 控制台
{ lib, ... }:
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
    font = "Lat2-Terminus16";
    keyMap = lib.mkDefault "us";
    useXkbConfig = true; # 让 TTY 复用 xkb.options
  };
}
