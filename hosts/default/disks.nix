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
                  # swapfile 大小: install.sh 安装时按内存重写为与内存等大
                  # (上取整; 休眠要求 swap ≥ 内存)。此值为分发默认,
                  # 直接 disko (不走 install.sh) 时同样有效。
                  swap.swapfile.size = "4G";
                };
                # 快照存储: @persist 的嵌套子卷 .snapshots (btrfs-assistant.nix 头注释):
                # snapper 的非顶层布局需要它以 /persist/.snapshots 下 ".snapshots" 结尾命名,
                # 嵌套布局可被 btrfs-assistant 自动推断 restore 目标, 无需手工映射。
                # 必须声明 (而非依赖 snapper 兜底 mkdir): 否则落成普通目录,
                # timeline 快照会递归拷贝整个 .snapshots 目录树。
                # mountpoint = null: 不生成挂载 (父 @persist 挂载后自然可见)。
                "@persist/.snapshots" = {
                  mountpoint = null;
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
