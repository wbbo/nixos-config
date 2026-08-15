# 家目录持久化(系统级)—— /persist/home/<mainUser> 预建 + cc-switch bind mount
# /persist 由 @persist 子卷提供 (snapper 保护), root 所有; home 激活钩子 (以 mainUser 运行)
# 无法在其中建目录, 故用 systemd.tmpfiles (boot 时以 root 创建) 预建并 chown。
# cc-switch 拒绝符号链接配置目录, 用 bind mount 使 ~/.cc-switch 为真实目录 (数据在 @persist)。
# 配合 modules/home/persist.nix 的迁移+符号链接钩子 (~/.claude 用 symlink)。
{ config, ... }:
{
  systemd.tmpfiles.rules = [
    # @persist 家目录根 (wbb 所有, 供 home 激活钩子迁移/symlink)
    "d /persist/home 0755 root root - -"
    "d /persist/home/${config.mainUser} 0700 ${config.mainUser} ${config.mainUser} - -"
    # cc-switch bind mount 的源目录 + 挂载点 (都需存在, 否则 mount 失败)
    "d /persist/home/${config.mainUser}/.cc-switch 0700 ${config.mainUser} ${config.mainUser} - -"
    "d /home/${config.mainUser}/.cc-switch 0700 ${config.mainUser} ${config.mainUser} - -"
    # docker 数据目录 (镜像/容器, root 所有)
    "d /persist/docker 0755 root root - -"
  ];

  # cc-switch: bind mount 使 ~/.cc-switch 为真实目录 (数据在 @persist, 跨重建保留)
  fileSystems."/home/${config.mainUser}/.cc-switch" = {
    device = "/persist/home/${config.mainUser}/.cc-switch";
    fsType = "none";
    options = [ "bind" "nofail" ];
  };
}
