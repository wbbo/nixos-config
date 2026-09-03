# SSH 用户密钥 —— sops secrets 声明式管理 (ssh-id-ed25519 / ssh-id-ed25519-pub)
# 激活钩子从 /run/secrets 再生 ~/.ssh/id_ed25519{,.pub}: 重装/换机后一份
# secrets.yaml 即恢复全部身份 (git 推拉 GitHub、ssh 跳板均依赖此密钥)。
#
# 权威源语义 (同 main-user-password): secrets.yaml 是唯一权威, 手动生成/
# 替换的 ~/.ssh/id_ed25519 会在下次激活被 secrets 版覆盖 —— 换密钥的正确
# 姿势是更新 secrets.yaml (见 secrets.template.yaml 的块标量格式)。
# 钩子只管 id_ed25519 两个文件; known_hosts/authorized_keys/config 等不碰。
# secrets 缺失 (分发模板首装未初始化) 时警告跳过, 不阻断激活。
{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.activation.ssh-identity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PRIV="$(${pkgs.coreutils}/bin/cat /run/secrets/ssh-id-ed25519 2>/dev/null || true)"
    PUB="$(${pkgs.coreutils}/bin/cat /run/secrets/ssh-id-ed25519-pub 2>/dev/null || true)"
    if [ -n "$PRIV" ] && [ -n "$PUB" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.ssh"
      ${pkgs.coreutils}/bin/chmod 700 "${config.home.homeDirectory}/.ssh"
      # %s\n: 命令替换会剥掉值末尾的换行, OpenSSH 私钥缺尾换行即
      # "invalid format" (实测) —— 必须补回一个终止换行
      ${pkgs.coreutils}/bin/printf '%s\n' "$PRIV" > "${config.home.homeDirectory}/.ssh/id_ed25519"
      ${pkgs.coreutils}/bin/chmod 600 "${config.home.homeDirectory}/.ssh/id_ed25519"
      ${pkgs.coreutils}/bin/printf '%s\n' "$PUB" > "${config.home.homeDirectory}/.ssh/id_ed25519.pub"
      ${pkgs.coreutils}/bin/chmod 644 "${config.home.homeDirectory}/.ssh/id_ed25519.pub"
    else
      echo "警告: ssh-id-ed25519(-pub) secret 缺失, SSH 用户密钥未配置" >&2
    fi
  '';
}
