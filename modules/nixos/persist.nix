# 家目录持久化(系统级)—— neededForBoot 标记
# 目录持久化主体由 impermanence 接管 (flake input, NixOS 模块自动给
# home-manager.sharedModules 注入 home.persistence 选项):
# modules/home/persist.nix 用 home.persistence."/persist".directories 声明,
# boot 期以 root bind mount 到 ~/<dir>。
# impermanence 断言要求 / 与 /persist 都标记 neededForBoot = true
# (disko 生成的 fileSystems 未设置, 下方 mkForce 覆盖默认 false)。
# /persist/home 与 /persist/home/<mainUser> 的预建 (0700 属主) 由 impermanence
# 的 createPersistentStorageDirs activation script 负责, 不再手写 tmpfiles。
# 本文件只保留 impermanence 覆盖不到的部分:
# - docker 数据目录预建 (数据就在 /persist/docker, 不做挂载遮蔽)
# (原 cc-switch 手写 bind 已并入 modules/home/persist.nix 的 impermanence
#  声明 —— cc-switch 虽拒 symlink, 但 impermanence 目录持久化即 bind,
#  行为等价; 权限按 /persist 源端 0700 wbb 复制)
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
    # docker 数据目录 (镜像/容器, root 所有)
    "d /persist/docker 0755 root root - -"
  ];

  # impermanence 断言: 持久化卷与挂载目标卷都必须 neededForBoot
  fileSystems."/".neededForBoot = lib.mkForce true;
  fileSystems."/persist".neededForBoot = lib.mkForce true;
}
