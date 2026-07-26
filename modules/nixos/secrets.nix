# sops-nix 集成: 声明式 secret 管理
# 加密的 secrets 文件签入 git, 部署时由主机 age 密钥自动解密到 /run/secrets/
{ config, ... }:
{
  sops = {
    # 默认 secrets 文件 (相对于 flake root)
    defaultSopsFile = ../../secrets/secrets.yaml;

    # age 密钥路径 — install.sh 在 chroot 内写入此文件
    # nixos-install 期间: /root 指向 /mnt/root, 密钥由 install.sh 阶段 1 写入
    # 首次启动后: /root 指向系统 root, 密钥已持久化
    age.keyFile = "/root/.config/sops/age/keys.txt";

    secrets = {
      ### GitHub token netrc
      # Nix flake 拉取 GitHub inputs 时自动携带 token, 避免未认证 403
      github-netrc = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      ### 用户密码哈希
      # 依赖 /run/secrets/wbb-password-hash 在用户登录前就绪
      wbb-password-hash = {
        neededForUsers = true;
      };
    };
  };
}
