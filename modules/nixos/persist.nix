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
{ config, lib, pkgs, ... }:
{
  # uid/gid 分配表持久化 (impermanence): 根分区每次重启重置, 若不持久化
  # /var/lib/nixos, 未写死 uid 的用户 (wbb/greeter/rtkit...) 每次重启
  # 重新分配 ID → /persist 持久化文件属主错位。迁移前需先拷贝现有数据:
  #   sudo mkdir -p /persist/var/lib/nixos && sudo cp -a /var/lib/nixos/. /persist/var/lib/nixos/
  environment.persistence."/persist".directories = [
    "/var/lib/nixos"

    # libvirt 虚拟机数据 (qcow2 磁盘镜像 / nvram / swtpm 状态)。
    # 不持久化时重装 (@ 子卷重建) 会连虚拟机带盘一起丢失。
    #
    # ⚠ /persist/var/lib/libvirt 必须是**独立 btrfs 子卷**, 不是普通目录。
    # snapper 保护整个 @persist, 而 btrfs 快照是浅快照、不递归包含嵌套子卷 ——
    # 这是把虚拟机镜像排除在时间线快照外的唯一办法 (否则 38G 的 qcow2 会被
    # 几十个快照反复钉住, 空间持续膨胀; 实测过一次: 22 个快照钉住 38GiB)。
    # 重建该目录时**必须**用 `btrfs subvolume create`, 不可用 mkdir;
    # 也不要在 disks.nix 里给它加递归快照。此事实无法在 nix 配置中表达,
    # 只能靠本注释维系 (2026-09-11 命令式创建, top level 257)。
    #   sudo btrfs subvolume create /persist/var/lib/libvirt
    #
    # 迁移顺序不能反: 必须**先拷贝数据再 rebuild**。反了的话 boot 期
    # bind mount 会遮蔽 @ 上的旧数据, impermanence 发现源目录不存在
    # 会建一个空的 /persist/var/lib/libvirt, libvirt 看到空目录重建默认
    # 结构, 虚拟机在列表里"消失" (旧数据仍在 @ 上, 未删除, 但需手工找回)。
    # 拷贝前先停 libvirtd (dnsmasq 占着 leases, 不停会挡 umount):
    #   sudo btrfs subvolume create /persist/var/lib/libvirt
    #   sudo cp -a /var/lib/libvirt/. /persist/var/lib/libvirt/
    "/var/lib/libvirt"
  ];

  systemd.tmpfiles.rules = [
    # docker 数据目录 (镜像/容器, root 所有)
    "d /persist/docker 0755 root root - -"
  ];

  # impermanence 断言: 持久化卷与挂载目标卷都必须 neededForBoot
  fileSystems."/".neededForBoot = lib.mkForce true;
  fileSystems."/persist".neededForBoot = lib.mkForce true;

}
