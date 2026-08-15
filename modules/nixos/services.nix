# 系统服务:SSH / 蓝牙 / 电源 / nix-ld
{ ... }:
{
  services.openssh.enable = true;
  services.blueman.enable = true;
  services.power-profiles-daemon.enable = true;

  # nix-ld: 提供 /lib /lib64 真实 glibc 加载器兼容, 让非 NixOS 二进制
  # (如 VS Code Remote-SSH 的 vscode-server) 能运行
  programs.nix-ld.enable = true;
}
