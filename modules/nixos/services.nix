# 系统服务:SSH / 蓝牙 / 电源 / nix-ld
{ ... }:
{
  services.openssh.enable = true;
  # ⚠ openFirewall 默认 true 会把 22 偷偷加回 networking.firewall.allowedTCPPorts
  # (全局放行), 让 networking.nix 的来源白名单形同虚设 —— 实测 firewall-start
  # 里两条 --dport 22 并存才抓到。必须显式关。
  services.openssh.openFirewall = false;
  # 仅密钥认证: 22 端口按 networking.nix 的白名单仅对固定管理机开放, 密码
  # 爆破面归零。authorized_keys 由 secrets.nix 的激活钩子声明式自愈 (sops
  # ssh-id-ed25519-pub 注入 root+mainUser, 指纹与本机私钥一致), 锁密码不影响
  # 自用。2026-09-20 前实测 sshd_config 为 PasswordAuthentication yes。
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };

  # 临时密码登录开关: sshd 配置为首次匹配生效 —— 全局 no 先设置, Match 组内
  # 的 yes 只对组成员生效 (非成员无感)。开关本体是组成员的动态增删
  # (ssh-temp-password on|off, 见 ssh-temp-password.nix), 不需要 reload sshd。
  # Match 块必须放 extraConfig 最前 —— Match 之后的所有行都属于其作用域。
  services.openssh.extraConfig = ''
    Match Group temp-ssh-password
        PasswordAuthentication yes
        KbdInteractiveAuthentication yes
  '';
  # 组必须与 Match 同批声明 (sshd 启动时校验 Match Group 指向的组存在,
  # 不存在则拒绝启动)。members 留空 = 默认无人可用密码登录;
  # ssh-temp-password on 动态加入的用户在 rebuild/重启后可能被声明复位
  # (可预期行为: 临时授权自动过期, off 命令兜底)。
  users.groups.temp-ssh-password = { };
  services.blueman.enable = true;
  services.power-profiles-daemon.enable = true;

  # MCE (机器检查异常) 记录解码 —— i9-13900KF 存在 Vmin Shift 不可逆劣化
  # (2026-09 确诊: 随机用户态 SIGSEGV + MCE, nix/claude/pigma/rime_deployer
  # 多进程受累), rasdaemon 持续解码 MCE 供观测缓解效果与劣化速度:
  #   ras-mc-ctl --summary / --errors
  # (26.05 module 位于 hardware.rasdaemon, 非 services.hardware)
  hardware.rasdaemon.enable = true;

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
