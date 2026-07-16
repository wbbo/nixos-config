# sops-nix 集成: 声明式 secret 管理
# 加密的 secrets 文件签入 git, 部署时由主机 age 密钥自动解密到 /run/secrets/
{ config, ... }:
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
      github-netrc = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      ### 主用户密码哈希
      # 依赖 /run/secrets/main-user-password-hash 在用户登录前就绪
      main-user-password-hash = {
        neededForUsers = true;
      };
    };
  };
}
