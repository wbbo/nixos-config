# git 用户配置(HM 26.05: 统一使用 programs.git.settings)
# 身份跟随主用户名 (mainUser), 邮箱可按需修改
{ mainUser, ... }:
{
  programs.git = {
    enable = true;
  };
  programs.git.settings = {
    init.defaultBranch = "main";
    user = {
      name = mainUser;
      email = "${mainUser}@localhost"; # TODO: 改成你的真实邮箱
    };
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
    diff.algorithm = "histogram";
  };
}
