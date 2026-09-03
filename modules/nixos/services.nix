# 系统服务:SSH / 蓝牙 / 电源 / nix-ld
{ ... }:
{
  services.openssh.enable = true;
  services.blueman.enable = true;
  services.power-profiles-daemon.enable = true;

  # logind 对合盖不动作 (不挂起; 锁屏由 niri switch-events 执行,
  # 见 modules/home/niri/config.kdl)。台式机无 lid 事件, 无害。
  # 26.05 起旧选项 services.logind.lidSwitch* 已废弃, 改用 settings.Login 映射
  # logind.conf 的 HandleLidSwitch*。注意三项默认值独立: battery=suspend,
  # external-power=suspend, docked=ignore —— 只设主项时插电合盖仍会挂起
  # (曾踩坑), 故三项显式全设 ignore。
  # 想要合盖挂起的机器在 local.nix 用 mkForce 覆盖为 "suspend"。
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # nix-ld: 提供 /lib /lib64 真实 glibc 加载器兼容, 让非 NixOS 二进制
  # (如 VS Code Remote-SSH 的 vscode-server) 能运行
  programs.nix-ld.enable = true;
}
