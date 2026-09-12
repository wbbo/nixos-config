# Flatpak + GNOME Software —— 通用 Linux 应用分发(与 Nix 包互补)
# Flatpak 应用沙箱隔离, 解决 nixpkgs 未打包 / 更新慢的闭源应用 (如聊天/办公软件)。
# 系统级安装到 /var/lib/flatpak (普通可写目录, 跨 rebuild 保留);
# 安装授权走 polkit (认证代理: Noctalia 内建, 见 home/programs/noctalia.nix)。
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

  # 必需 Flatpak 应用自动补装 —— 应用本体装在 /var/lib/flatpak (系统盘,
  # 重装/格式化即丢), 而应用数据 (~/.var/app/<app>) 在 persist.nix 持久化,
  # 补装应用本体即可恢复完整状态:
  #   - com.usebottles.bottles: 企业微信的 wine 前端 (bottle 本体 11G 在
  #     persist, 含已配置的企业微信 + runner + 组件)
  #   - com.tencent.WeChat: 微信官方 Linux 版 (聊天记录/登录态在 persist)
  # 开机 3 分钟检查, 缺哪个装哪个 (已装秒退, 幂等); 之后每 15 分钟复查,
  # 失败/网络波动自动重试。首次补齐可能下载数百 MB (含 runtime),
  # TimeoutStartSec 放宽到 30 分钟; 与 flatpak-flathub 同样依赖 mihomo
  # (TUN 未就绪时拉取会 SSL connect error)。
  # 注: 只补装不自动更新 —— 升级仍走手动 flatpak update (与仓库惯例一致)。
  systemd.services.flatpak-apps = {
    description = "Install required Flatpak apps if missing";
    after = [ "network-online.target" "mihomo.service" "flatpak-flathub.service" ];
    wants = [ "network-online.target" "mihomo.service" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "1800";
    };
    # 注意用 if ! 而非 `cmd && continue`: 后者在条件为假时整个列表返回非零,
    # 若脚本被以 set -e 执行会直接终止 (同款陷阱在 gh 钩子踩过)
    script = ''
      for app in com.usebottles.bottles com.tencent.WeChat; do
        if ! flatpak info --system "$app" >/dev/null 2>&1; then
          flatpak install --system --noninteractive flathub "$app" || true
        fi
      done
    '';
  };
  systemd.timers.flatpak-apps = {
    description = "Periodically ensure required Flatpak apps are installed";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3m";
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
