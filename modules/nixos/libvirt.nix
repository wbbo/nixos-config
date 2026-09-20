# libvirt + virt-manager —— QEMU/KVM 虚拟机管理
# libvirtd 组已由 users.nix 的 extraGroups 统一管理, 此处不重复。
# GUI 为 GTK (virt-manager), Wayland 原生运行; CLI 用 virsh / virt-install。
{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true; # vTPM (Windows 11 安装需要); OVMF 已默认随 QEMU 提供
    };
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
