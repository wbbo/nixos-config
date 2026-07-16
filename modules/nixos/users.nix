# 用户账户: 主用户(见 ./main-user.nix) + root 应急密码
{ pkgs, config, ... }:
{
  # root 应急密码: 当主用户的 sops 解密失败时仍有入口
  # 用 mkpasswd -m yescrypt 生成, 需要从 secrets 中提取
  users.users.root = {
    # 从 secrets 解密后的密码文件读取 (和主用户共用同一个密码)
    hashedPasswordFile = config.sops.secrets.main-user-password-hash.path;
    # 如果 secrets 解密失败, root 依然被锁定 (安全考虑)
    # 届时需用 Live ISO chroot 恢复
  };

  users.users.${config.mainUser} = {
    description = config.mainUser;
    isNormalUser = true;
    home = "/home/${config.mainUser}";
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;

    # 密码哈希由 sops-nix 解密注入 (来源: secrets/secrets.yaml)
    hashedPasswordFile = config.sops.secrets.main-user-password-hash.path;

    extraGroups = [
      "wheel" # sudo
      "networkmanager"
      "audio"
      "input"
      "video"
      "docker"
      "kvm"
      "libvirtd"
    ];

    # greetd 以系统服务启动 niri，需要 linger 保持用户 systemd 实例常驻
    # （pipewire、user timer 等服务需要用户实例运行）
    linger = true;
  };
}
