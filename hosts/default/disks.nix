# 声明式磁盘布局 —— 配合 disko (github:nix-community/disko) 使用
#
# install.sh 在安装时将 DISK_DEVICE_PLACEHOLDER 替换为目标磁盘路径,
# 然后调用: nix run github:nix-community/disko -- --mode zap_create_mount
#
# 修改子卷或挂载选项: fileSystems 由 disko 模块自动生成, 无需手动同步。
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "DISK_DEVICE_PLACEHOLDER";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              extraArgs = [ "-F" "32" "-n" "ESP" ];
              mountpoint = "/boot";
              mountOptions = [ "fmask=0077" "dmask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" "-L" "nixos" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd:3" "noatime" ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd:3" "noatime" ];
                };
                "@persist" = {
                  mountpoint = "/persist";
                  mountOptions = [ "compress=zstd:3" "noatime" ];
                };
                "@swap" = {
                  mountpoint = "/swap";
                  mountOptions = [ "noatime" ];
                  swap.swapfile.size = "16G";
                };
                "@snapshots" = {
                  mountpoint = "/.snapshots";
                  mountOptions = [ "noatime" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
