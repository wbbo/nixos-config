# btrfs-assistant 修复 —— Browse/Restore 的 target 下拉为空。
#
# 三层原因与对应修复:
#
# 1. 程序枚举挂载子卷用两条裸命令名 (`btrfs filesystem show -m` /
#    `findmnt --real -t btrfs`), 依赖 PATH; 而 launcher 经 pkexec 提权会把环境
#    重置为 polkit 编译期默认 PATH (/usr/sbin:/usr/bin:/sbin:/bin)。NixOS 上
#    /usr/bin 只有 env、/bin 只有 sh → 两条命令找不到 → 枚举失败。
#    snapper 的调用 nixpkgs 打包时已硬编码为 store 绝对路径, 故 Snapper 标签页
#    正常, 仅 Browse/Restore 受影响。→ overlay 在包层 wrapProgram 注入 PATH。
#    (上游问题: Arch 下 /usr/bin/btrfs 天然存在所以无感)
#
# 2. 程序枚举子卷前要求文件系统顶层 (subvolid=5) 已挂载: mountRoot 发现未挂载
#    时会自行临时挂载, 但实测该路径静默失败 (strace: findmnt subvolid=5 之后
#    无 mount 执行即返回空), 导致整个 FS 被 continue 跳过 —— 这是 target 下拉
#    为空的最终断点。→ 声明式常驻挂载顶层到 /mnt/btrfs-root, mountRoot 直接
#    命中现有挂载 (也是 btrfs 快照管理工具生态的通用最佳实践)。
#
# 3. 本机 snapper 布局原为独立子卷 @snapshots (挂 /persist/.snapshots), 枚举出
#    的快照路径形如 `@snapshots/<n>/snapshot`, 其映射目标 (target 子卷) 只能由
#    /etc/btrfs-assistant.conf 的 [Subvol-Mapping] 提供, 程序的布局 fallback
#    (快照子卷路径以 "/.snapshots" 结尾时取其父子卷为目标) 不认 "@" 命名。
#    → 布局迁移 (2026-09-26): 废弃独立 @snapshots, 快照目录改为 @persist 下的
#      嵌套子卷 `.snapshots` (路径 `@persist/.snapshots/<n>/snapshot`) —— 以
#      "/.snapshots" 结尾精确命中程序的 fallback 分支, restore 目标自动推断为
#      父子卷 @persist, 无需任何手工映射。disks.nix 已同步删除独立子卷声明。
#      此布局即 snapper 上游默认的嵌套布局; 独立子卷的意义 (快照与数据卷互不
#      拖累) 让位于工具链兼容。
#      (曾尝试用 /etc/btrfs-assistant.conf 动态写入映射替代布局迁移: conf 由
#       activation 脚本生成, 文件读取经 strace 确认正常, 但 QSettings 解析/匹配
#       一层无法穿透, 放弃)
#      恢复语义经源码核对 (Btrfs::restoreSubvol): 恢复 @persist 自身时, 程序先
#      记录直接子代 (.snapshots), rename @persist → @persist_backup_<ts> 后再把
#      子代从 backup rename 回新 @persist —— .snapshots 快照库连同全部历史快照
#      自动迁回; 子代 rename 失败时程序会显式报错提示手动迁移 (本布局仅一个
#      直接子代, 一次 rename 完成, 该分支正常不触发)。
{ lib, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      btrfs-assistant = prev.btrfs-assistant.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/btrfs-assistant-bin \
            --prefix PATH : ${lib.makeBinPath [ final.btrfs-progs final.util-linux ]}
        '';
      });
    })
  ];

  fileSystems."/mnt/btrfs-root" = {
    # LABEL 寻址: disko 格式化时固定 -L nixos, 跨重装稳定; subvolid=5 为
    # 文件系统顶层 (所有子卷的父), 挂上后可见全部子卷树
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvolid=5" "noatime" ];
  };
}
