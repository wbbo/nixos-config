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
  # ssh 客户端配置 (**混合模式**, 2026-10-10):
  #   ~/.ssh/config    可写实体主文件 (运行时区) —— 首行 Include 声明式片段,
  #                    其余为 VSCode "Add New SSH Host" / 手动追加的 Host,
  #                    **跨 rebuild/重启持久保留** (远程设备随时变化);
  #   ~/.ssh/config.hm 只读声明式片段 —— 本文件 settings 渲染 (含 "*" 默认段),
  #                    rebuild 即更新。
  # 起因: Remote-SSH 连接/添加主机时 open(O_WRONLY) 写 ~/.ssh/config, 撞
  # HM 的只读 store 软链报 `EROFS: read-only file system, open '~/.ssh/config'`。
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

  # 重定向 HM 生成物落点 (config.hm), 让 ~/.ssh/config 本体成为「用户侧文件」
  # (HM 不再软链/管理它)。激活钩子只做 **seed + 自愈**, 不覆盖内容:
  #   - 缺失 (首装) / 仍是旧软链 (修复前代际) / Include 行被外部工具抹掉
  #     (极端: VSCode 整体重写文件) → 重建为 seed 版 (单行 Include);
  #   - 其余时间不碰文件 → 运行时新增的条目持久保留。
  # 声明式更新不经钩子: config.hm 每次激活由 HM 更新, 改上方 settings 即生效。
  # 顺序语义 (OpenSSH first-match wins): Include 展开在前, 运行时追加的块在后
  # —— HostName/User/Port 等普通参数不受影响; 想**覆盖** "*" 段已有参数
  # (如 Compression) 要写进 settings, 追加到主文件不生效 (踩到时回来看这句)。
  # ⚠ 三处不可擅动: ① target 重定向 (移除 = 软链回归, EROFS 复现); ② 钩子
  # 排在 linkGeneration 之后 (见 home-manager/modules/files.nix 的激活顺序);
  # ③ Include 用 eval 期展开的绝对路径 (分发模板自动适配接收者家目录)。
  home.file.".ssh/config".target = ".ssh/config.hm";
  home.activation.ssh-config-mutable = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    cfg="${config.home.homeDirectory}/.ssh/config"
    # 旧代际的软链 (→ 只读 store): 先删, 否则重定向写入会撞只读文件系统
    if [ -L "$cfg" ]; then
      ${pkgs.coreutils}/bin/rm -f "$cfg"
    fi
    if [ ! -e "$cfg" ] || ! ${pkgs.gnugrep}/bin/grep -qF "config.hm" "$cfg"; then
      ${pkgs.coreutils}/bin/printf 'Include %s\n' "${config.home.homeDirectory}/.ssh/config.hm" > "$cfg"
      ${pkgs.coreutils}/bin/chmod 600 "$cfg"
    fi
  '';

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
