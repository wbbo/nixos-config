# Bootloader: GRUB (UEFI) + os-prober
# 双盘双 ESP (Windows 在 nvme0n1p1 独立 ESP): systemd-boot 只扫自身 ESP,
# 无法自动探测 Windows; grub 的 os-prober 全盘扫描, 跨盘 chainload bootmgfw.efi。
# 代价: 无 BLS boot counting 自动回滚 (新 generation 损坏需手动选旧条目)。
#
# 主题: vinceliuice/grub2-themes 官方 nixosModule —— 构建期生成主题包,
# 自动接线 boot.loader.grub.theme/splashImage/gfxmode, 无需跑上游 install.sh。
# 可选 theme: tela/vimix/stylish/whitesur; icon: color/white/whitesur;
# screen 需与显示器匹配 (3840x2160 → 4k)。
{ inputs, ... }:
{
  imports = [ inputs.grub2-themes.nixosModules.default ];

  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";          # 双盘 UEFI: 只写 ESP, 不碰 MBR
      useOSProber = true;        # 全盘探测 Windows (跨盘跨 ESP)
      default = "saved";         # 记住上次选择的系统 (grubenv 记录, 不默认回 NixOS)
    };
    grub2-theme = {
      enable = true;
      theme = "tela";            # tela (上游默认) / vimix / stylish / whitesur
      icon = "white";            # 深色背景配白色单色 logo
      screen = "4k";             # 当前显示器 3840x2160
    };
    efi.canTouchEfiVariables = true;
    timeout = 5;
  };
}
