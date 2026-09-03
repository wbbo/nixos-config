# 硬件配置 —— 通用示例 (分发模板)
# 真实硬件配置由 install.sh 在安装时自动检测生成并覆盖本文件
{ lib, modulesPath, ... }:
{
  # 文件系统支持 —— 从 hosts/default/disks.nix 自动推导
  boot.initrd.supportedFilesystems = [ "btrfs" "vfat" ];
  boot.initrd.availableKernelModules = [
    # SCSI/VMware HBA: 覆盖 LSI Logic (spi)、PVSCSI 等, 防止模板被同步到已装机后 initrd 找不到根盘
    "mptspi" "mptscsih" "scsi_transport_spi" "sym53c8xx"
    "vmw_pvscsi" "mpt3sas" "mpt2sas" "megaraid_sas"
    "ahci" "nvme" "sd_mod" "usb_storage" "usbhid" "uas"
    "xhci_pci" "ehci_pci" "iwlwifi" "iwlmvm" "iwldvm"
  ];
  # 具体内核模块在安装时自动检测, 此处保持通用 (CPU 微码固定双开于 modules/nixos/hardware.nix)
  # 分发默认 x86_64; install.sh 安装时按 Live CD 架构 (uname -m) 重写,
  # ARM 机器 (aarch64 等) 自动适配。不能省略: nixpkgs 的 hostPlatform 无默认值。
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
