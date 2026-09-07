# 文件系统 / 休眠 / zram —— 引导时内核配置
{ config, lib, pkgs, ... }:

let
  # 唤醒侧: 内核恢复休眠镜像早于 initrd, 只认 cmdline 的 resume=
  # (boot.resumeDevice) 与 resume_offset= (boot.kernelParams 静态值)。
  # 休眠执行走 hibernate-now 直写内核 (见下), 不经过 systemd 休眠栈。

  resumeDevice = "/dev/disk/by-label/nixos";

  # 手动休眠: 直写 sysfs 走内核 S4, 绕过 systemd 260 休眠栈。
  # 背景: 260 + 内核 6.18 新挂载 API 下 btrfs 挂载点 st_dev 为 anonymous
  #   (0:49 而非 8:2), systemd 按 devno 匹配 swap 条目恒失败, CanHibernate
  #   判定返回 "na", systemctl hibernate 被 logind 拒绝。内核直通不受影响
  #   (resume 只认 cmdline 的 resume=/resume_offset=)。唤醒恢复与
  #   systemd-sleep 钩子脱钩: 网络等由 NetworkManager 自恢复, 可接受。
  # 用法: sudo hibernate-now (sudoers 已放行 mainUser 免密)。
  hibernateNow = pkgs.writeShellApplication {
    name = "hibernate-now";
    runtimeInputs = [ pkgs.btrfs-progs pkgs.util-linux pkgs.niri ];
    text = ''
      set -euo pipefail

      # 先 DPMS 关屏: 内核写入休眠镜像的几秒里 GPU 尚未断电,
      # 屏幕会"黑→亮→黑"闪烁; 提前关屏让整个休眠过程保持黑色。
      if [ -n "''${SUDO_USER:-}" ]; then
        SOCK=$(find "/run/user/$(id -u "$SUDO_USER")" -maxdepth 1 \
          -name 'niri.wayland-1.*.sock' -print -quit 2>/dev/null || true)
        if [ -n "$SOCK" ]; then
          NIRI_SOCKET="$SOCK" niri msg action power-off-monitors 2>/dev/null || true
          sleep 0.2
        fi
      fi

      DEVICE="${resumeDevice}"
      if [ ! -e "$DEVICE" ]; then
        echo "hibernate-now: device $DEVICE not found" >&2
        exit 1
      fi

      # 每次休眠前动态探测偏移: btrfs balance 移动 swapfile 后仍正确
      TMP="$(mktemp -d)"
      trap 'umount "$TMP" 2>/dev/null; rmdir "$TMP"' EXIT
      mount -t btrfs -o subvol=@swap,noatime "$DEVICE" "$TMP"
      OFFSET=$(btrfs inspect-internal map-swapfile -r "$TMP/swapfile")

      if [ -z "$OFFSET" ] || [ "$OFFSET" -le 0 ] 2>/dev/null; then
        echo "hibernate-now: failed to read swapfile offset" >&2
        exit 1
      fi

      echo "$OFFSET" > /sys/power/resume_offset
      # 断电模式用 shutdown (内核直关) 而非默认 platform (ACPI S4):
      # platform 下固件进入 S4 后若已有 pending 唤醒事件 (键鼠/PCIe 设备,
      # 本机 XHCI/PEG/RP* 全 enabled) 会立即弹回原会话不断电 —— 实测踩坑
      # (Saving NVS → Creating image → 未断电直接 Waking up from S4)。
      # shutdown 模式写完镜像直接 poweroff, 不受 pending 唤醒影响;
      # 唤醒侧不受影响 (resume 只认 cmdline, 与 /sys/power/disk 无关)。
      echo shutdown > /sys/power/disk
      echo "hibernate-now: resume_offset=$OFFSET, hibernating" >&2
      echo disk > /sys/power/state
    '';
  };
in
{
  ### 文件系统:支持 btrfs(挂载由 hardware-configuration.nix 声明)
  boot.supportedFilesystems = [ "btrfs" ];

  # 硬件模块 (initrd/kernel) 由 hosts/default/hardware-configuration.nix
  # 提供 —— install.sh 调用 nixos-generate-config 自动生成。本文件只含
  # 文件系统/休眠/zram 等架构无关配置。

  ### 休眠:resume 到 btrfs swapfile(label "nixos",install.sh 格式化时设 -L)
  boot.resumeDevice = resumeDevice;

  ### systemd initrd: 提供干净的启动流程
  boot.initrd.systemd.enable = true;

  ### 安静启动: 静默内核消息与 systemd 状态输出
  # greetd/tuigreet 跑在 tty1, 内核 console 也是 tty1 —— 不静默的话
  # "[ OK ] Started xxx" 会直接打在 tuigreet 的 TUI 界面上覆盖登录框。
  # quiet 让 systemd 自动关 show_status (=loglevel 4, 只显示 err 及更严重);
  # loglevel=5 额外放行 warning 级 (打印条件: 消息级别 < loglevel, 数字越大越安静)。
  # 主噪音源已修复 (微码/固件/nouveau 见 hardware.nix), 剩余 ACPI BIOS bug
  # (XHC _PLD) 与 spi-nor 属 err 级, 5 挡不住, 需更安静时降为 2。
  # 排查启动问题时临时移除本参数即可 (journalctl -b 不受影响, 消息仍完整记录)。
  # boot.kernelParams = [ "loglevel=5" ];

  ### 禁用 watchdog (硬件狗 + NMI watchdog)
  # 高负载偶发 soft lockup 误报, TCO 硬件狗在休眠/唤醒或时间漂移时可能误触发
  # 重启; 家用台式机无需硬件看门狗。iTCO_wdt = Intel 平台, sp5100_tco = AMD 平台
  #
  # resume_offset: btrfs swapfile 物理偏移 (页, 由 `btrfs inspect-internal
  # map-swapfile -r /swap/swapfile` 现查)。内核恢复休眠镜像时从 cmdline 读此值
  # (systemd 260 不再读 /sys/power/resume_offset, 休眠执行由 hibernate-now
  # 直写内核, 唤醒侧必须 cmdline 静态提供)。@swap 子卷专用且无快照/压缩,
  # 偏移长期稳定; btrfs balance 移动 swapfile 或换盘重装后需重查更新。
  # 注: hibernate-now 每次休眠前动态探测并写运行时 resume_offset, 与静态值
  # 同源, 仅当两者不一致 (balance 后未更新) 时唤醒会失败。
  boot.kernelParams = [
    "nmi_watchdog=0"
    # 值为最近一次探测实测 (探测失败时的回退, 与运行时 hibernate-now 动态探测
    # 同源)。swapfile 重建/balance 移动后此值会过期 —— build.sh 构建期注入
    # 保证系统侧始终新鲜, 仓库回退值需在重建 swapfile 后手工同步一次。
    "resume_offset=34743552"
  ];
  boot.blacklistedKernelModules = [ "iTCO_wdt" "iTCO_vendor_support" "sp5100_tco" ];

  ### zram:内存压缩交换
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  ### hibernate-now: 免密 sudo (mainUser 触发内核直通休眠)
  # systemd 260 休眠栈不可用 (见 hibernateNow 注释), 脚本需 root (挂载 btrfs
  # + 写 /sys/power/*)。仅放行本脚本, 不动其他 sudo 权限。
  # 注意: ① sudo 匹配命令时不解析 symlink, 用户敲 `sudo hibernate-now` 落到
  # /run/current-system/sw/bin 的软链, 规则必须写该稳定路径 (store 路径条目
  # 不生效, 已实测); ② sw/bin 由 root 独占写入, 无提权风险。
  environment.systemPackages = [ hibernateNow ];
  security.sudo.extraRules = [
    {
      users = [ config.mainUser ];
      commands = [
        {
          command = "/run/current-system/sw/bin/hibernate-now";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
