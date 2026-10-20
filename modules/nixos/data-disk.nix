# 数据盘 (机械盘) —— sdb 单分区 btrfs, LABEL=data 寻址, 挂载 /data。
#
# 文件系统不在 rebuild 里创建 (disko 只在安装时执行, rebuild 不会格式化),
# 首次使用需手工一次性完成:
#   sfdisk /dev/sdb              # GPT + 单分区, 脚本输入: label: gpt / ,+,L
#   mkfs.btrfs -f -L data /dev/sdb1
#   mount -o compress=zstd:3,noatime /dev/disk/by-label/data /data
# 之后本模块负责挂载声明, 重启自动挂载。
#
# 自动适配有无第二块盘 (无盘时零 failed 单元): /data 挂载单元用 systemd.mounts
# 声明并带 ConditionPathExists —— 设备不存在时条件不满足, 单元直接 skipped
# (不是 failed, systemctl --failed 不列出), boot 不受影响。Bottles 数据目录由
# bottles-data 服务按运行时条件挂载: 有盘 /data, 无盘回退 /persist (仍持久化)。
# 不能只用 fileSystems + nofail: nofail 只保证不阻塞 boot, 单元本身仍会进入
# failed 状态。也不能在 Nix eval 期检测: nixos-rebuild 是纯 eval,
# builtins.pathExists 对 /dev 下的绝对路径恒返回 false (实测), 只有 --impure
# 才能看到真实设备, 因此检测只能交给 systemd 在运行时完成。
{ config, lib, pkgs, ... }:
let
  cfg = config.dataDisk;
in
{
  options.dataDisk = {
    # 默认启用: 有盘机器自动挂载, 无盘机器条件跳过 (见文件头注释)。
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "启用数据盘 /data 与 Bottles bind (无盘时条件跳过)";
    };

    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-label/data";
      description = "数据盘设备路径 (默认按 LABEL 寻址, 换接口/重装后保持稳定)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.mounts = [
      {
        what = cfg.device;
        where = "/data";
        type = "btrfs";
        # 与系统盘同款挂载参数: zstd 压缩省空间 (机械盘写放大可忽略), noatime
        # 减少无谓写回。不开 autodefrag —— 对机械盘只会加剧随机写。
        options = "compress=zstd:3,noatime";
        wantedBy = [ "local-fs.target" ];
        before = [ "local-fs.target" ];
        unitConfig.ConditionPathExists = cfg.device;
      }
    ];

    # Bottles (flatpak) 数据目录: 有盘挂 /data, 无盘挂 /persist —— 两种都是持久化。
    # 为什么不用 impermanence 管这个目录: 它的 HM 激活 bind 晚于 local-fs, 会在
    # 有盘时叠加一层 /persist bind 遮住 /data 的数据; 且它的清单无法按运行时
    # 条件切换。为什么用 bind 而不是符号链接: flatpak 启动时由 bubblewrap 以
    # RESOLVE_BENEATH 解析 ~/.var/app/<appid>, 绝对符号链接会被拒绝
    # ("absolute symlink not allowed for RESOLVE_BENEATH"), 应用直接启动失败;
    # bind mount 对沙盒是普通目录, 透明无感。
    # 该服务总是成功 (无盘时回退 /persist), 因此不会产生 failed 单元。
    systemd.services.bottles-data = {
      description = "Bind-mount Bottles data dir (data disk if present, else /persist)";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.util-linux pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        target=/home/${config.mainUser}/.var/app/com.usebottles.bottles
        mkdir -p "$target"
        if mountpoint -q /data; then
          src=/data/bottles
          mkdir -p "$src"
        else
          # 无盘: 落到 @persist (snapper 保护, 重装/回滚保留)
          src=/persist/home/${config.mainUser}/.var/app/com.usebottles.bottles
          mkdir -p "$src"
        fi
        if ! mountpoint -q "$target"; then
          mount --bind "$src" "$target"
        fi
        chown ${config.mainUser}:${config.mainUser} "$src" "$target"
      '';
    };

    # bind 挂载点的父目录: 重装后 @root 上的 .var/app 不存在时, systemd 无法
    # 创建挂载点。tmpfiles 在 sysinit 阶段先建好 (早于 local-fs 挂载)。
    systemd.tmpfiles.rules = [
      "d /home/${config.mainUser}/.var/app 0755 ${config.mainUser} ${config.mainUser} -"
    ];
  };
}
