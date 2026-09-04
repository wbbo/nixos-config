# git 用户配置(HM 26.05: 统一使用 programs.git.settings)
# 提交身份 (user.name/user.email) 不在此硬编码: 走 sops secrets
# (git-user-name/git-user-email), 激活钩子生成 ~/.config/git/identity,
# 经 programs.git.includes 引用 —— 分发模板不含个人身份, 接收者只改 secrets.yaml。
# HM 生成的 ~/.config/git/config 是 store 只读链接, 无法运行时写入, 故用
# include 文件而非直接 settings.user (见下方激活钩子)。
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # gitui: 终端 git TUI (Rust, 声明式安装)
  # subversion: SVN 客户端 (svn, 公司仓库仍走 SVN)
  # git-filter-repo: 历史重写 (替代弃用 filter-branch, LFS 历史瘦身)
  # gh / glab: GitHub / GitLab CLI
  home.packages = with pkgs; [
    gitui
    subversion
    git-filter-repo
    gh
    glab
  ];

  # delta: 语法高亮 diff pager (enableGitIntegration 自动写 core.pager
  # + interactive.diffFilter 到 ~/.gitconfig, git diff/log 彩色分页)
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  programs.git = {
    enable = true;
    # git svn 子命令 (svnSupport, git svn clone/dcommit/rebase) + libsecret
    # 凭据助手 (withLibsecret, HTTPS 凭据存 GNOME keyring) + withSsh (硬编码
    # ssh 路径, maintenance timer 等 systemd 单元环境不依赖 PATH 找 ssh):
    # 替换默认 git 包。与 packages.nix 系统层参数一致 → 同一 store 路径。
    package = pkgs.git.override {
      svnSupport = true;
      withLibsecret = true;
      withSsh = true;
    };
    # git maintenance 后台维护 (prefetch/commit-graph/gc): 大仓库
    # status/log 明显提速; systemd user timers 默认 hourly/daily/weekly
    maintenance = {
      enable = true;
      repositories = [
        "${config.home.homeDirectory}/code/nixos-config"
        "${config.home.homeDirectory}/code/vsct"
        "${config.home.homeDirectory}/code/isid"
      ];
    };
    # 注册 filter.lfs.* 并安装 git-lfs；全局 ~/.config/git/config 只读，
    # git lfs install 无法自行写入（仓库级已用 --local 兜底）
    lfs.enable = true;
    # git 身份经 include 注入 (文件由激活钩子从 /run/secrets 生成);
    # 文件缺失时 git 静默忽略 include, 首装未初始化 secrets 也不报错
    includes = [
      { path = "${config.home.homeDirectory}/.config/git/identity"; }
    ];
  };
  programs.git.settings = {
    init.defaultBranch = "main";
    alias = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      sw = "switch";
      lg = "log --oneline --graph --decorate --all";
    };
    pull.rebase = true;
    push.autoSetupRemote = true;
    core.editor = "nvim";
    # 换行符: 检出不转换, 提交时 CRLF → LF (core.autocrlf=input)
    core.autocrlf = "input";
    diff.algorithm = "histogram";
    # HTTPS 凭据存 GNOME keyring (withLibsecret 构建的 git-credential-libsecret);
    # SSH 协议仓库不受影响
    credential.helper = "libsecret";
  };

  # git 身份激活钩子: 从 sops secrets 生成 identity include 文件。
  # writeBoundary = HM 文件写链完成后, 每次激活运行 (幂等覆写);
  # secrets 缺失 (分发模板首装未初始化) 时警告跳过, 不阻断激活。
  home.activation.git-identity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    NAME="$(${pkgs.coreutils}/bin/cat /run/secrets/git-user-name 2>/dev/null || true)"
    EMAIL="$(${pkgs.coreutils}/bin/cat /run/secrets/git-user-email 2>/dev/null || true)"
    if [ -n "$NAME" ] && [ -n "$EMAIL" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.config/git"
      ${pkgs.coreutils}/bin/printf '[user]\n\tname = %s\n\temail = %s\n' "$NAME" "$EMAIL" \
        > "${config.home.homeDirectory}/.config/git/identity"
      ${pkgs.coreutils}/bin/chmod 600 "${config.home.homeDirectory}/.config/git/identity"
    else
      echo "警告: git-user-name/git-user-email secret 缺失, git 提交身份未配置" >&2
    fi
  '';
}
