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
  programs.git = {
    enable = true;
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
