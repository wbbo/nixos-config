# 用户账户: 主用户(见 ./main-user.nix) + root 应急密码
# 密码方案: secrets.yaml 存明文 (sops 加密), 激活时派生 yescrypt 哈希注入 /etc/shadow。
# 注意: update-users-groups.pl 对 hashedPasswordFile 的内容原样写入 shadow 不再哈希,
# 必须喂哈希 —— passwordFile 选项在 nixpkgs 26.05 已是 hashedPasswordFile 的废弃别名,
# 喂明文会导致明文落入 /etc/shadow 且 pam 验证失败 (root+主用户全部锁死)。
{ pkgs, config, ... }:
{
  # 完全声明式密码管理: 每次激活强制覆盖 shadow 哈希
  # (手动 passwd 改的会被回写; 改密码 = 编辑 secrets → rebuild)
  users.mutableUsers = false;

  # 明文 → yescrypt 哈希派生: 排在 setupSecretsForUsers (解密 neededForUsers
  # secrets) 之后、users 段 (update-users-groups.pl) 之前。
  # users.deps 是 list, 与 sops-nix 对 users.deps 的追加合并同法。
  system.activationScripts.main-user-password-hash = {
    deps = [ "setupSecretsForUsers" ];
    text = ''
      PW_SRC=${config.sops.secrets.main-user-password.path}
      HASH_OUT=/run/main-user-password-hash
      # umask 必须限制在子 shell 内: activation 所有段共用同一 bash 进程,
      # 全局 umask 会泄漏给后续 users 段, 把 /etc/passwd 等重写成 0600 (全系统 NSS 失效)
      if [ -s "$PW_SRC" ]; then
        # stdin 传入, 避免明文出现在 /proc/<pid>/cmdline; mkpasswd 会 chomp 尾换行
        (umask 077; ${pkgs.mkpasswd}/bin/mkpasswd -m yescrypt --stdin < "$PW_SRC" > "$HASH_OUT")
      else
        # secret 缺失/为空 (分发模板未初始化): 锁定密码登录, 需 Live ISO chroot 恢复
        echo '!' > "$HASH_OUT"
        chmod 0600 "$HASH_OUT"
        echo "warning: main-user-password 未就绪, ${config.mainUser}/root 密码锁定" >&2
      fi
    '';
  };
  system.activationScripts.users.deps = [ "main-user-password-hash" ];

  # root 应急密码: 当主用户的 sops 解密失败时仍有入口
  # 和主用户共用同一份密码; secret 缺失时派生为 '!' → 锁定
  users.users.root = {
    hashedPasswordFile = "/run/main-user-password-hash";
  };

  users.users.${config.mainUser} = {
    description = config.mainUser;
    isNormalUser = true;
    # 主组与用户名一致 (默认 NixOS 是 users, 这里不写死)
    group = config.mainUser;
    home = "/home/${config.mainUser}";
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;

    # yescrypt 哈希由上方 activationScripts 从明文 secret 派生
    hashedPasswordFile = "/run/main-user-password-hash";

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

    # linger 保持用户 systemd 实例常驻: boot 期 home-manager-<user>.service
    # 即被拉起 (激活钩子在无人登录时运行, nixos-rebuild 的强制重跑也依赖,
    # 见 home-manager.nix); 登出后 pipewire、user timer 等服务不中断
    linger = true;
  };

  # 同名主组
  users.groups.${config.mainUser} = {};
}
