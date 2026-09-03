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

  programs.virt-manager.enable = true;
}
