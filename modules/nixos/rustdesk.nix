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
    # ⚠ 不能写 After=graphical.target (或 wantedBy=graphical.target): 本单元
    # wantedBy=multi-user.target, systemd 会隐式补 Before=multi-user.target,
    # 而 graphical.target 标准地 After=multi-user.target —— 三者成环:
    #   rustdesk → multi-user → graphical → rustdesk
    # 症状: nixos-rebuild 切换时报 "Transaction order is cyclic"
    # (graphical.target 启动失败, 退出码 4); 上次切换侥幸靠 systemd 删作业绕过,
    # 换一次事务就绕不过。2026-09-17 实测 (system-13 那次切换 exit 4)。
    # 远控服务本身无需等桌面: 屏幕捕获走 xdg-desktop-portal (连接时才需要会话,
    # 那时桌面早已就绪), 守护进程开机起在 multi-user 即可。
    after = [ "network.target" ];
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
