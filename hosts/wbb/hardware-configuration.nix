# 硬件配置 —— 由 install.sh 自动生成
{ config, lib, pkgs, modulesPath, ... }:
{
  # 文件系统支持 —— 从 hosts/wbb/disks.nix 自动推导
  boot.initrd.supportedFilesystems = [ "btrfs" "vfat" ];
  boot.initrd.availableKernelModules = [
    "ahci" "nvme" "sd_mod" "usb_storage" "usbhid" "uas"
    "xhci_pci" "ehci_pci" "iwlwifi" "iwlmvm" "iwldvm"
  ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
  hardware.cpu.intel.updateMicrocode = true;
  hardware.cpu.amd.updateMicrocode = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
