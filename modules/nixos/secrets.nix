# sops-nix 集成: 声明式 secret 管理
# 加密的 secrets 文件签入 git, 部署时由主机 age 密钥自动解密到 /run/secrets/
{ config, pkgs, ... }:
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

      ### 主用户密码哈希
      # 依赖 /run/secrets/main-user-password-hash 在用户登录前就绪
      main-user-password-hash = {
        neededForUsers = true;
      };

      ### cc-switch S3 (Cloudflare R2) 云同步凭据
      # 供 cc-switch.nix 激活钩子读取并执行 config s3 set (以 mainUser 运行, 故 owner 设为 mainUser)
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

      ### mihomo 订阅 URL
      # 由 mihomo.nix activationScripts 读入并注入生成的 config.yaml (root 读)
      mihomo-subscription-url = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
      ### mihomo API secret (WebUI/外部控制)
      mihomo-api-secret = {
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
}
