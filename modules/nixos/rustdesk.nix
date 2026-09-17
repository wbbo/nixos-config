# RustDesk —— 开源远控 (替代 wine 跑 Windows 版 ToDesk, 后者在 wine 下启动即页错误崩溃,
# 见 doc/wework.md 测试记录)。
#
# 角色: 被控端为主 (手机/其他电脑远控本机), 亦可作主控。
#
# 两个组成部分:
#   1. 包本身 (environment.systemPackages) —— 主控端开箱即用;
#   2. root 常驻服务 (`rustdesk --service`) —— 被控端必需:
#      - Wayland 下的键鼠注入走 uinput, 需 root 权限 (wbb 已在 input 组, 但
#        服务模式是官方被控形态: 登录前可连、无人值守)
#      - 无 nixpkgs NixOS module, 手写 unit, 对齐官方 deb 自带的
#        rustdesk.service (Type=simple + Restart=always)
#
# Wayland (niri) 被控的屏幕捕获: 走 xdg-desktop-portal-gnome 的 ScreenCast
# (desktop.nix 已配, niri 实现 Mutter ScreenCast 接口)。首次连接会在桌面弹
# portal 授权对话框, 选择屏幕后可记住选择。
# 注意: RustDesk 设置里需手动开启 "Wayland" (检测到 Wayland 时 UI 会提示)。
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.rustdesk ];

  systemd.services.rustdesk = {
    description = "RustDesk Service (remote control daemon)";
    after = [ "network.target" "graphical.target" ];
    wants = [ "graphical.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.rustdesk}/bin/rustdesk --service";
      Restart = "always";
      RestartSec = 5;
      PIDFile = "/run/rustdesk.pid";
      StandardOutput = "null";
      StandardError = "null";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
