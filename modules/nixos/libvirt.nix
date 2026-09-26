# libvirt + virt-manager —— QEMU/KVM 虚拟机管理
# libvirtd 组已由 users.nix 的 extraGroups 统一管理, 此处不重复。
# GUI 为 GTK (virt-manager), Wayland 原生运行; CLI 用 virsh / virt-install。
{ pkgs, lib, ... }:
{
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

  # virtiofs 共享目录 —— libvirt 靠 vhost-user JSON 数据库发现 virtiofsd
  # (读 /var/lib/qemu/vhost-user/*.json, 非 PATH 探测)。libvirtd 模块的
  # vhostUserPackages 默认空, 该目录建出来就是空的 → start 报
  # "Unable to find a satisfying virtiofsd"。把 virtiofsd 加进去 (其包内自带
  # 50-virtiofsd.json), module 经 buildEnv symlink 到位 (win11 VM 的
  # host 共享目录 ~/vm-share 走它)。
  virtualisation.libvirtd.qemu.vhostUserPackages = [ pkgs.virtiofsd ];

  programs.virt-manager.enable = true;
}
