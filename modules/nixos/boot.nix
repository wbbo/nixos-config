# 文件系统 / 休眠 / zram —— 引导时内核配置
{ config, lib, pkgs, ... }:

let
  # initrd 阶段自动检测 btrfs swapfile 的 resume_offset 并写入 sysfs。
  #
  # 背景: systemd-hibernate-resume 在 btrfs 上不自动发现 swapfile
  #   偏移(上游 commit 477fc07d 有意避免引入 btrfs-progs 依赖),
  #   而内核必须在 /sys/power/resume_offset 拿到该值才能恢复休眠。
  #
  # 方案: 在 systemd-hibernate-resume.service 之前运行一个 oneshot
  #   service, 临时挂载 @swap 子卷, 用 btrfs map-swapfile 检测偏移,
  #   写入 /sys/power/resume_offset, 然后卸载。全自动, 不绑死具体
  #   磁盘/机器, 换盘后重建即适配。

  resumeDevice = "/dev/disk/by-label/nixos";

  detectResumeOffset = pkgs.writeShellApplication {
    name = "detect-resume-offset";
    runtimeInputs = [ pkgs.btrfs-progs ];
    text = ''
      set -euo pipefail

      DEVICE="${resumeDevice}"

      # 等待块设备就绪
      if [ ! -e "$DEVICE" ]; then
        echo "detect-resume-offset: device $DEVICE not found, skipping" >&2
        exit 0
      fi

      TMP="$(mktemp -d)"
      trap 'umount "$TMP" 2>/dev/null; rmdir "$TMP"' EXIT

      mount -t btrfs -o subvol=@swap,noatime "$DEVICE" "$TMP"
      OFFSET=$(btrfs inspect-internal map-swapfile -r "$TMP/swapfile")

      if [ -n "$OFFSET" ] && [ "$OFFSET" -ne 0 ] 2>/dev/null; then
        echo "$OFFSET" > /sys/power/resume_offset
        echo "detect-resume-offset: resume_offset=$OFFSET" >&2
      else
        echo "detect-resume-offset: failed to read swapfile offset" >&2
      fi
    '';
  };
in
{
  ### 文件系统:支持 btrfs(挂载由 hardware-configuration.nix 声明)
  boot.supportedFilesystems = [ "btrfs" ];

  # 硬件模块 (initrd/kernel/CPU 微码) 由 hosts/wbb/hardware-configuration.nix
  # 提供 —— install.sh 调用 nixos-generate-config 自动生成。本文件只含
  # 文件系统/休眠/zram 等架构无关配置。

  ### 休眠:resume 到 btrfs swapfile(label "nixos",install.sh 格式化时设 -L)
  boot.resumeDevice = resumeDevice;

  ### systemd initrd: 提供干净的启动流程
  boot.initrd.systemd.enable = true;

  ### initrd 阶段自动检测 btrfs swapfile resume_offset
  # 在 systemd-hibernate-resume 之前运行, 仅当 swapfile 可读时写入 sysfs
  boot.initrd.systemd.packages = [ pkgs.btrfs-progs ];
  boot.initrd.systemd.contents = {
    "/detect-resume-offset" = {
      source = "${detectResumeOffset}/bin/detect-resume-offset";
    };
  };
  boot.initrd.systemd.services.detect-resume-offset = {
    description = "Detect btrfs swapfile resume_offset";
    wantedBy = [ "initrd.target" ];
    before = [ "systemd-hibernate-resume.service" ];
    after = [ "initrd-root-device.target" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/detect-resume-offset";
      RemainAfterExit = "yes";
    };
  };

  ### zram:内存压缩交换
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
