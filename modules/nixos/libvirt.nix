# libvirt + virt-manager —— QEMU/KVM 虚拟机管理
# libvirtd 组已由 users.nix 的 extraGroups 统一管理, 此处不重复。
# GUI 为 GTK (virt-manager), Wayland 原生运行; CLI 用 virsh / virt-install。
{ pkgs, lib, ... }:
{
  # spice-gtk Wayland 鼠标补丁 (patches/spice-gtk-wayland-mouse.patch)
  # ---------------------------------------------------------------------
  # 症状: virt-manager / remote-viewer 的 SPICE 控制台里, 指针可见可移动,
  #       但**点击完全无效**(键盘正常; guest 侧正常 —— QEMU 注入实测可点击)。
  #
  # 三层根因 (2026-09-28 定位, 每层都有日志/源码证据):
  #   1. spice-gtk 0.42 把 `GdkEventButton.state` 直接当按键掩码发给服务端,
  #      而 GDK-Wayland 按下事件的 state **不含刚按下的键**(实测 press=0x0 /
  #      release=0x100) → 服务端收到的永远是"没有键按下"。
  #      → 补丁①: 按下 `| button_mask`、抬起 `& ~button_mask`
  #        (X11 下 state 本就含该键, 按位或幂等, 不影响 X11)
  #   2. spice-gtk 客户端**默认主动请求 client mouse mode**(channel-main.c:267
  #      `requested_mouse_mode = SPICE_MOUSE_MODE_CLIENT`, 1692 行还会持续重试)
  #      → 即使删掉 VM 的 USB tablet, 客户端一连上就又把它拉回 client mode。
  #   3. spice-server 0.16 (inputs-channel.cpp) 在 client mode 下**普通按键
  #      只有 vdagent 一条通路**: press 分支有 agent → reds_handle_agent_mouse_event,
  #      否则只调 tablet 的 wheel(), 普通按键直接丢弃。本机 guest 的 vdagent
  #      注入进不了 Windows(公司终端安全软件拦合成输入的嫌疑最大) → 点击全丢。
  #      → 补丁②: 改为请求 **server mode**; 该模式下按键经 `sif->motion/buttons`
  #        直接写入 QEMU 设备状态, 完全绕开 vdagent; 且相对指针路径用的
  #        `d->mouse_button_mask` 源码里本就维护正确(|= / ^=), 双重保险。
  #
  # 配套 VM 侧改动: win11 域的 USB tablet 已移除(server mode 不需要它, 也避免
  # 设备把模式拉回 client), 配置备份在 ~/win11-xml-backup-*.xml。
  # 副作用: server mode 下指针是相对模式(在窗口内被抓取, Ctrl+Alt 释放)。
  nixpkgs.overlays = [
    (final: prev: {
      spice-gtk = prev.spice-gtk.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../../patches/spice-gtk-wayland-mouse.patch ];
      });
    })
  ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true; # vTPM (Windows 11 安装需要); OVMF 已默认随 QEMU 提供
    };
  };

  # 按需启动 (socket 激活): libvirtd 不随开机启动 —— 客户端 (virt-manager /
  # virsh) 连接 /run/libvirt/libvirt-sock 时由 systemd 唤醒
  # (libvirtd.socket 由模块置于 sockets.target, 监听 socket 近零成本)。
  # 模块已设 --timeout 120 (注释 "from libvirt/var/lib/sysconfig/libvirtd"):
  # 该参数仅在 socket 激活模式下生效 —— 无连接/无活动 VM 时空闲 2 分钟自动
  # 退出, 无人使用时真正零常驻; 有 VM 在跑时 daemon 不退出, 不受影响。
  systemd.services.libvirtd.wantedBy = lib.mkForce [ ];
  # libvirt-guests (负责开机自动启动 autostart 的 VM) 同样去掉: 它每次开机都会
  # 连接 libvirt, 反而把刚休眠的 libvirtd 唤醒。将来若有 VM 需要开机自启,
  # 删除下面这行即可。
  systemd.services.libvirt-guests.wantedBy = lib.mkForce [ ];
  # 执行体 no-op 化 (彻底静音): 该单元的 stop 脚本 (libvirt-guests.sh) 会尝试
  # 连接 libvirt URI, 本机未配置任何 URI 时打印 "Can't connect to default.
  # Skipping." 到控制台/journal (2026-09-26 清理残影时可见)。脚本对每次
  # start/stop 都会执行该连接 (LISTFILE 机制不提供持久短路), 且 nixpkgs 模块
  # 无 onShutdown=ignore 之类的开关 (enum 仅 shutdown/suspend, 脚本也不识别
  # ignore) —— 本机 0 VM 且不管理 autostart, 该单元本无任何职责, 直接以
  # no-op 替换执行体, 从源头消除提示。ExecStart 列表首项空串 = 清空包内
  # unit 的原指令 (nixpkgs 覆盖包单元的惯用法; 不清空会变成追加执行)。
  systemd.services.libvirt-guests.serviceConfig = {
    ExecStart = [ "" "${pkgs.coreutils}/bin/true" ];
    ExecStop = [ "" "${pkgs.coreutils}/bin/true" ];
  };

  # guest ↔ 宿主机 传文件走 SSH —— guest 内直接 ssh/scp 到宿主机 sshd
  # (192.168.122.1:22; 防火墙全局放行 22, 见 networking.nix)。
  # 不配置 virtiofs 共享目录: 需要 guest 侧额外安装 virtio-win 的 virtiofs
  # 驱动 + WinFsp, 成本高于收益 (原 vhostUserPackages = [ virtiofsd ] 与
  # ~/vm-share 目录已随之废弃)。

  programs.virt-manager.enable = true;
}
