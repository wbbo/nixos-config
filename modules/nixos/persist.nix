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
  ];

  systemd.tmpfiles.rules = [
    # docker 数据目录 (镜像/容器, root 所有)
    "d /persist/docker 0755 root root - -"
  ];

  # impermanence 断言: 持久化卷与挂载目标卷都必须 neededForBoot
  fileSystems."/".neededForBoot = lib.mkForce true;
  fileSystems."/persist".neededForBoot = lib.mkForce true;

  # impermanence 的 bind mount 被 udisks2 上报为"挂载卷" —— Nautilus 等文件
  # 管理器遂把持久化目录 (apps/code/go/Pictures/screenshot 等非隐藏项) 以卷
  # 图标显示在侧边栏。给它们补 x-gvfs-hide 挂载选项即让 GVFS 忽略 (选项经
  # /run/mount/utab 被 libmount 读取, 实测有效: remount 后该挂载从
  # `gio mount -l` 消失)。impermanence 的 unit 走 mount(2) 无法带自定义
  # 选项, 故开机后 remount 补一次 (幂等, 失败不阻塞启动)。
  # 隔离性: 只匹配「挂载点在家目录下 且 源含 @persist」的 bind mount ——
  # 外接 U 盘/硬盘 (/run/media/*, 源为 /dev/sdX) 不满足任一条件, 其显示与
  # udisks 免密挂载完全不受影响; 且只 remount 不卸载, 不触碰数据。
  systemd.services.hide-persist-mounts = {
    description = "Hide impermanence bind mounts from GVFS/udisks2";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.util-linux}/bin/findmnt -rno TARGET,SOURCE |
        ${pkgs.gawk}/bin/awk '$1 ~ "^/home/" && $2 ~ /@persist/ { print $1 }' |
        while read -r p; do
          ${pkgs.util-linux}/bin/mount -o remount,bind,x-gvfs-hide "$p" 2>/dev/null || true
        done
    '';
  };
}
