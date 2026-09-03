# 家目录持久化(系统级)—— neededForBoot 标记 + cc-switch bind mount
# 目录持久化主体由 impermanence 接管 (flake input, NixOS 模块自动给
# home-manager.sharedModules 注入 home.persistence 选项):
# modules/home/persist.nix 用 home.persistence."/persist".directories 声明,
# boot 期以 root bind mount 到 ~/<dir>。
# impermanence 断言要求 / 与 /persist 都标记 neededForBoot = true
# (disko 生成的 fileSystems 未设置, 下方 mkForce 覆盖默认 false)。
# /persist/home 与 /persist/home/<mainUser> 的预建 (0700 属主) 由 impermanence
# 的 createPersistentStorageDirs activation script 负责, 不再手写 tmpfiles。
# 本文件只保留 impermanence 覆盖不到的部分:
# - .cc-switch bind mount (cc-switch 拒绝符号链接; 保留手写以维持
#   nofail 兜底 + tmpfiles 预建行为, 已验证)
# - docker 数据目录预建 (数据就在 /persist/docker, 不做挂载遮蔽)
{ config, lib, ... }:
{
  # uid/gid 分配表持久化 (impermanence): 根分区每次重启重置, 若不持久化
  # /var/lib/nixos, 未写死 uid 的用户 (wbb/greeter/rtkit...) 每次重启
  # 重新分配 ID → /persist 持久化文件属主错位。迁移前需先拷贝现有数据:
  #   sudo mkdir -p /persist/var/lib/nixos && sudo cp -a /var/lib/nixos/. /persist/var/lib/nixos/
  environment.persistence."/persist".directories = [
    "/var/lib/nixos"
  ];

  systemd.tmpfiles.rules = [
    # cc-switch bind mount 的源目录 + 挂载点 (都需存在, 否则 mount 失败)
    "d /persist/home/${config.mainUser}/.cc-switch 0700 ${config.mainUser} ${config.mainUser} - -"
    "d /home/${config.mainUser}/.cc-switch 0700 ${config.mainUser} ${config.mainUser} - -"
    # docker 数据目录 (镜像/容器, root 所有)
    "d /persist/docker 0755 root root - -"
  ];

  # impermanence 断言: 持久化卷与挂载目标卷都必须 neededForBoot
  fileSystems."/".neededForBoot = lib.mkForce true;
  fileSystems."/persist".neededForBoot = lib.mkForce true;

  # cc-switch: bind mount 使 ~/.cc-switch 为真实目录 (数据在 @persist, 跨重建保留)
  fileSystems."/home/${config.mainUser}/.cc-switch" = {
    device = "/persist/home/${config.mainUser}/.cc-switch";
    fsType = "none";
    options = [ "bind" "nofail" ];
  };
}
