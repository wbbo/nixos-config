# sops-nix 集成: 声明式 secret 管理
# 加密的 secrets 文件签入 git, 部署时由主机 age 密钥自动解密到 /run/secrets/
{ config, lib, pkgs, ... }:
{
  sops = {
    # 默认 secrets 文件 (相对于 flake root)
    defaultSopsFile = ../../secrets/secrets.yaml;

    # 方案 B: 用 SSH 主机密钥替代 age 密钥对
    # sops-install-secrets 自动从 host key 派生 age 密钥解密,
    # 无需单独的 age keys.txt (依赖 .sops.yaml 中的 host key age 公钥)
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      ### GitHub token netrc
      # Nix flake 拉取 GitHub inputs 时自动携带 token, 避免未认证 403
      # owner=mainUser: netrc 认证在 nix 客户端进程 (curl) 应用,
      # 非特权 `nix flake update` 也要能读; root (nixos-rebuild) 不受权限限制
      ### GitHub 凭据 (netrc 由 systemd github-netrc 服务生成三条目)
      github-username = {
        owner = config.mainUser;
        mode = "0400";
      };
      github-token = {
        owner = config.mainUser;
        mode = "0400";
      };

      ### git 提交身份 (user.name / user.email)
      # git.nix 激活钩子读取并生成 ~/.config/git/identity (programs.git.includes
      # 引用)。分发模板不含个人身份 —— 接收者在 secrets.yaml 填自己的。
      git-user-name = {
        owner = config.mainUser;
        mode = "0400";
      };
      git-user-email = {
        owner = config.mainUser;
        mode = "0400";
      };

      ### SSH 用户密钥 (id_ed25519 私钥 + 公钥)
      # ssh.nix 激活钩子再生 ~/.ssh/id_ed25519{,.pub}: 重装/换机一份 secrets
      # 恢复全部身份。私钥 YAML 块标量多行存储 (同 mihomo-subscription-url 先例)。
      ssh-id-ed25519 = {
        owner = config.mainUser;
        mode = "0400";
      };
      ssh-id-ed25519-pub = {
        owner = config.mainUser;
        mode = "0644";
      };

      ### 主用户密码 (明文, sops 加密保护)
      # users.nix 激活时 mkpasswd 转 yescrypt 哈希注入 /etc/shadow (secrets 保持明文可维护)
      # neededForUsers: 解密到 /run/secrets-for-users/ (早于 users 段就绪; mihomo API secret 复用此路径)
      main-user-password = {
        neededForUsers = true;
      };

      ### cc-switch S3 (Cloudflare R2) 云同步凭据
      # 供 cc-switch-install 用户服务读取并执行 config s3 set (服务以 mainUser
      # 身份运行, 故 owner 设为 mainUser)
      cc-switch-s3-access-key-id = {
        owner = config.mainUser;
        mode = "0400";
      };
      cc-switch-s3-secret-access-key = {
        owner = config.mainUser;
        mode = "0400";
      };
      # 站点特定配置 (R2 account/bucket, 换账户只改 secrets.yaml)
      cc-switch-s3-bucket = {
        owner = config.mainUser;
        mode = "0400";
      };
      cc-switch-s3-endpoint = {
        owner = config.mainUser;
        mode = "0400";
      };

      ### mihomo 订阅 URL 列表 (YAML 块标量字符串, 每行一条)
      # 由 mihomo.nix activationScripts 按行解析, 生成 provider1/provider2/... (root 读)
      # mihomo API secret 复用 main-user-password (见 mihomo.nix), 不再单独定义
      mihomo-subscription-url = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };

  # 从 github-username + github-token 生成三条目 netrc
  # (netrc 协议需每个 host 独立 machine, 无法在值内合并;
  #  只填一次 user+token, 三个 host 由服务生成, boot 时运行)
  systemd.services.github-netrc = {
    description = "Generate GitHub netrc (three hosts)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "github-netrc-gen" ''
        TOKEN=$(cat /run/secrets/github-token)
        USER=$(cat /run/secrets/github-username)
        umask 077
        : > /run/secrets/github-netrc
        for host in api.github.com github.com codeload.github.com; do
          echo "machine $host login $USER password $TOKEN" >> /run/secrets/github-netrc
        done
        chown ${config.mainUser}:users /run/secrets/github-netrc
        chmod 0400 /run/secrets/github-netrc
      '';
    };
  };

  # ssh-id-ed25519-pub 注入 root 与 mainUser 的 ~/.ssh/authorized_keys
  # (append 语义: 已有内容一律保留, 键已存在则跳过 —— 激活每次开机都跑,
  #  无去重会反复堆积重复行)。/root 位于 tmpfs/临时根, 每次开机由本钩子
  #  再生, 与 secrets 的声明式自愈语义一致。secret 缺失 (首装未初始化) 静默跳过。
  system.activationScripts.ssh-authorized-keys =
    lib.stringAfter [ "users" "var" "setupSecrets" ] ''
      PUB="$(${pkgs.coreutils}/bin/cat /run/secrets/ssh-id-ed25519-pub 2>/dev/null || true)"
      if [ -n "$PUB" ]; then
        # root (属主 root:root; /root 每次开机再生)
        ${pkgs.coreutils}/bin/mkdir -p /root/.ssh
        ${pkgs.coreutils}/bin/chmod 700 /root/.ssh
        ${pkgs.coreutils}/bin/touch /root/.ssh/authorized_keys
        ${pkgs.coreutils}/bin/chmod 600 /root/.ssh/authorized_keys
        # grep 在 gnugrep 而非 coreutils (路径写错 = 命令 127 = 去重失效反复追加, 实测)
        ${pkgs.gnugrep}/bin/grep -qxF -e "$PUB" /root/.ssh/authorized_keys \
          || ${pkgs.coreutils}/bin/echo "$PUB" >> /root/.ssh/authorized_keys
        # mainUser (属主 mainUser; HM ssh-identity 钩子仅管 id_ed25519, 不碰此文件)
        U_HOME="$(${pkgs.getent}/bin/getent passwd ${config.mainUser} | ${pkgs.coreutils}/bin/cut -d: -f6)"
        if [ -n "$U_HOME" ] && [ -d "$U_HOME" ]; then
          ${pkgs.coreutils}/bin/mkdir -p "$U_HOME/.ssh"
          ${pkgs.coreutils}/bin/chmod 700 "$U_HOME/.ssh"
          ${pkgs.coreutils}/bin/touch "$U_HOME/.ssh/authorized_keys"
          ${pkgs.coreutils}/bin/chmod 600 "$U_HOME/.ssh/authorized_keys"
          ${pkgs.gnugrep}/bin/grep -qxF -e "$PUB" "$U_HOME/.ssh/authorized_keys" \
            || ${pkgs.coreutils}/bin/echo "$PUB" >> "$U_HOME/.ssh/authorized_keys"
          ${pkgs.coreutils}/bin/chown ${config.mainUser}:users "$U_HOME/.ssh" "$U_HOME/.ssh/authorized_keys"
        fi
      fi
    '';
}
