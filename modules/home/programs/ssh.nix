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
  # ssh 客户端配置 (HM 管理, ~/.ssh/config 为 store 只读链接; 本机原先无此文件)。
  # github.com 重写到 ssh.github.com:443 —— mihomo TUN (fake-ip) 下 22 端口
  # 被拦 (实测 Connection closed by 198.18.0.5), 443 放行; 仓库既有 remote
  # 已是 ssh://git@ssh.github.com:443/... 形式, 此重写补上 git@github.com:...
  # 形式 (gh 的 git_protocol=ssh 生成的 clone URL、手敲的简写) 的连通性。
  # 只影响 ssh 客户端; sshd/authorized_keys 等与本文件无关。
  programs.ssh = {
    enable = true;
    # matchBlocks 已废弃 (HM 新版改用 settings: 键为 Host 名, 值用 OpenSSH
    # 上游指令名 Hostname/Port/User, 非旧的 camelCase)。
    # enableDefaultConfig=false 关闭隐式默认值注入 (消除 evaluation warning),
    # 下方 "*" 段即 HM 原默认值照抄 —— 与迁移前的 ssh 行为完全等价。
    enableDefaultConfig = false;
    settings = {
      "*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
      "github.com" = {
        Hostname = "ssh.github.com";
        Port = 443;
        User = "git";
      };
    };
  };

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
