# nixos-config

基于 **NixOS 26.05 Flakes** 的个人桌面配置。合成器 **[Niri](https://github.com/YaLTeR/niri)** (scrollable-tiling Wayland compositor) + **[Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)** (面板/通知/启动器/锁屏, 替代 waybar+mako+swaybg)。文件系统 btrfs 五子卷, 由 `install.sh` 手工分区管理。

## 目录结构

```
nixos-config/
├── flake.nix                       # Flakes 入口
├── install.sh                      # 一键安装脚本 (分区 + 硬件检测 + nixos-install)
├── hosts/
│   └── wbb/                        # 主机 wbb
│       ├── configuration.nix       # 入口: 导入硬件配置 + 系统模块 + Home Manager
│       └── hardware-configuration.nix   # 由 install.sh 生成, 不纳入版本控制
├── modules/
│   ├── nixos/                      # 系统级模块 (<nixpkgs/nixos/modules> 风格)
│   │   ├── default.nix             #   导入所有子系统模块 (imports 列表)
│   │   ├── bootloader.nix          # systemd-boot (UEFI)
│   │   ├── boot.nix                # btrfs / 休眠 / zram / initrd 内核模块
│   │   ├── nix.nix                 # Flakes / GC / 教育网镜像 / unfree
│   │   ├── networking.nix          # 主机名 / NetworkManager / 防火墙
│   │   ├── locale.nix              # 时区 / 语言 / 控制台
│   │   ├── ime.nix                 # fcitx5 输入法系统级 (Wayland 协议)
│   │   ├── users.nix               # 用户 wbb
│   │   ├── hardware.nix            # GPU 加速 / 蓝牙
│   │   ├── sound.nix               # PipeWire
│   │   ├── fonts.nix               # 中文字体 + Nerd Font
│   │   ├── services.nix            # SSH / 蓝牙 / 电源管理
│   │   ├── greetd.nix              # greetd 登录管理器 → niri-session
│   │   ├── snapper.nix             # btrfs 自动快照 (@persist 时间线)
│   │   ├── desktop.nix             # Niri 系统级 / xdg portal / 光标主题
│   │   └── packages.nix            # 系统级软件包
│   └── home/                       # Home Manager 用户级模块
│       ├── default.nix             #   入口: 导入 niri 配置 + 各 program
│       ├── niri/                   # Niri 合成器配置
│       │   ├── default.nix         #   部署 config.kdl / binds.kdl / rule.kdl
│       │   ├── config.kdl          #   主配置 (截图/环境变量/spawn)
│       │   ├── binds.kdl           #   快捷键
│       │   └── rule.kdl            #   窗口规则
│       └── programs/               # 用户程序配置
│           ├── kitty.nix
│           ├── fish.nix
│           ├── fuzzel.nix
│           ├── git.nix
│           ├── firefox.nix
│           ├── fcitx5.nix          # fcitx5 + 雾凇拼音 (rime-ice)
│           ├── noctalia.nix        # Noctalia Shell
│           └── neovim.nix
```

## 全新安装 (install.sh)

`install.sh` 自动化整个安装流程: 手工分区 → 硬件检测 → git commit → nixos-install。

⚠️ **以下命令会清空目标磁盘全盘**。先用 `lsblk -d -o NAME,SIZE,TRAN,MODEL` 确认设备名。

```bash
# 启动 NixOS Live ISO, 联网, 克隆仓库
git clone https://github.com/wbbo/nixos-config.git /root/nixos-config
cd /root/nixos-config

# 一键安装 (--disk 指定目标磁盘)
sudo ./install.sh --disk /dev/sda

# 可选: 跳过确认 (-f)
sudo ./install.sh -d /dev/nvme0n1 -f

# 重启
reboot
```

## 日常使用

```bash
# 增量构建并切换 (同时应用系统 + Home Manager)
sudo nixos-rebuild switch --flake .#wbb

# 更新 flake inputs
nix flake update              # 更新所有
nix flake update nixpkgs      # 只更新 nixpkgs
```

> Home Manager 已通过 NixOS 模块 (`inputs.home-manager.nixosModules.home-manager`) 集成, `nixos-rebuild switch` 会同时应用系统与用户配置, 无需单独执行 `home-manager switch`。

## 个性化要点

| 项目 | 值 |
|------|-----|
| 主机名 | `wbb` |
| 用户 | `wbb` (wheel / networkmanager / audio / input / video / docker / kvm / libvirtd) |
| Shell | fish |
| 登录管理 | `greetd` → `niri-session` |
| 合成器 | Niri (scrollable-tiling Wayland) |
| Shell 面板 | Noctalia Shell (面板/通知/启动器/锁屏) |
| 输入法 | fcitx5 + 雾凇拼音 (rime-ice) 小鹤双拼 |
| 文件系统 | btrfs 五子卷 (`@root` / `@nix` / `@persist` / `@swap` / `@snapshots`), `compress=zstd:3` |
| 休眠 | btrfs swapfile 16G + zramSwap 50%, `resume_offset` 由 initrd 自动检测 |
| 快照 | Snapper 对 `@persist` 做时间线快照 |
| 时区 | `Asia/Shanghai` |
| Nix 镜像 | cernet 教育网镜像 + 官方 cache |

## 文件系统设计

分区方案由 `install.sh` 实现:

- **EFI**: 1G FAT32 (`/dev/sda1`)
- **btrfs**: 剩余全部空间 (`/dev/sda2`), label `nixos`
  - `@root` → `/` (临时根, 为 Impermanence 铺路)
  - `@nix` → `/nix` (Nix Store)
  - `@persist` → `/persist` (永久数据, Snapper 保护)
  - `@swap` → `/swap` (swapfile 16G, 无压缩/No_COW)
  - `@snapshots` → `/.snapshots` (Snapper 快照存储)

`resume_offset` 不硬编码 —— initrd 阶段自动用 `btrfs map-swapfile` 检测, 换盘后重建即适配。

## 安全提示

- `modules/nixos/users.nix` 中保存了用户密码哈希 (`$y$j9T$...`), 属敏感信息。生产环境建议改用 `sops-nix` / `agenix` 加密管理。
