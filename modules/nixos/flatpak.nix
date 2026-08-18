# Flatpak + GNOME Software —— 通用 Linux 应用分发(与 Nix 包互补)
# Flatpak 应用沙箱隔离, 解决 nixpkgs 未打包 / 更新慢的闭源应用 (如聊天/办公软件)。
# 系统级安装到 /var/lib/flatpak (普通可写目录, 跨 rebuild 保留);
# 安装授权走 polkit (polkit-gnome agent 已由 niri 拉起)。
# 依赖 xdg.portal (desktop.nix 已启用 wlr+gtk 双 portal, 模块断言要求)。
{ pkgs, ... }:
{
  services.flatpak.enable = true;

  # Flathub 远程仓库自动注册(完全自动化, 零人工命令):
  # - boot 后 2 分钟首次尝试 (mihomo TUN 已就绪, network-online 之后),
  # - 之后每 15 分钟由 timer 复查一次 (幂等), 首次失败/网络波动都自动恢复。
  # 依赖 mihomo: TUN 未接管时 remote-add 会 SSL connect error, 故 after+wants 排队。
  # 使用: flatpak search <应用> / flatpak install flathub <AppID> / flatpak update
  systemd.services.flatpak-flathub = {
    description = "Ensure Flathub remote is configured for Flatpak";
    after = [ "network-online.target" "mihomo.service" ];
    wants = [ "network-online.target" "mihomo.service" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };
  systemd.timers.flatpak-flathub = {
    description = "Periodically ensure Flathub remote is configured";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "15m";
      AccuracySec = "1m";
      Persistent = true;
    };
  };

  # GNOME Software —— Flatpak 图形化应用商店 (搜索/安装/更新)
  # NixOS 无 PackageKit 后端 (系统包由 Nix 管理), 该应用仅操作 Flatpak, 二者不冲突。
  environment.systemPackages = with pkgs; [
    gnome-software
  ];
}
