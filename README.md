# nixos-config

基于 **NixOS 26.05 Flakes** 的个人桌面配置。合成器 **[Niri](https://github.com/YaLTeR/niri)** (scrollable-tiling Wayland compositor) + **[Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)** v5 (面板/通知/启动器/锁屏/壁纸, 替代 waybar+mako+swaybg)。文件系统 btrfs 五子卷，由 [disko](https://github.com/nix-community/disko) 声明式管理 + `install.sh` 自动化安装。敏感信息由 [sops-nix](https://github.com/Mic92/sops-nix) + age 加密管理。

## 全新安装 (NixOS Live ISO)

安装分为两种场景：

| 场景 | 条件 | 步骤 |
|------|------|------|
| **A: 已有 age 私钥** | 从旧主机重装 / 已备份私钥 | [1](#a-已有-age-私钥) |
| **B: 全新安装** | 首次使用 / 没有 age 私钥 | [1](#b-全新安装无-age-私钥) |

---

### A: 已有 age 私钥

仓库中的 `secrets/secrets.yaml` 已加密，提供私钥即可安装。

```bash
# 1. 启动 Live ISO 并联网
ping -c 3 baidu.com

# 2. 克隆仓库
git clone https://github.com/wbbo/nixos-config.git ~/nixos-config
cd ~/nixos-config

# 3. 安装（-k 传入 age 私钥）
sudo ./install.sh --disk /dev/sda -k "AGE-SECRET-KEY-1你的私钥"

# 4. 重启
reboot
```

> **哪里获取私钥？** 旧主机上：
> ```bash
> sudo cat /root/.config/sops/age/keys.txt | grep AGE-SECRET-KEY-1
> ```
> 或者在密码管理器中找之前备份的 `AGE-SECRET-KEY-1...` 完整行。只有私钥才能解密 `secrets/secrets.yaml`，请务必保管好。

---

### B: 全新安装（无 age 私钥）

`install.sh` 自动生成 age 密钥对、更新 `.sops.yaml`、交互式设置密码——只需选磁盘。

```bash
# 1. 启动 Live ISO 并联网
ping -c 3 baidu.com

# 2. 克隆仓库
git clone https://github.com/wbbo/nixos-config.git ~/nixos-config
cd ~/nixos-config

# 3. 一键安装（自动生成密钥对 + 设置密码，运行中按提示交互）
sudo ./install.sh --disk /dev/sda

# 4. 重启
reboot
```

> **install.sh 运行时的交互：**
> - **age 密钥** — 选 `G` 自动生成（备份私钥！），或选 `P` 粘贴已有私钥
> - **用户密码** — 交互式输入两次，自动生成 yescrypt 哈希
> - **GitHub token** — 可选，用 `-t` 提前传入或跳过
>
> 首次启动后立刻备份 age 私钥：
> ```bash
> sudo cat /root/.config/sops/age/keys.txt
> # 把 AGE-SECRET-KEY-1 这行保存到密码管理器
> ```
>
> 如需静默安装（适合脚本化）：
> ```bash
> sudo ./install.sh -d /dev/sda -f -k "AGE-SECRET-KEY-1..." -p '$y$j9T$...'
> ```

---

## 日常使用

```bash
# 构建并切换（同时应用系统 + Home Manager）
sudo nixos-rebuild switch --flake .#wbb

# 更新 flake inputs
nix flake update              # 更新所有
nix flake update nixpkgs      # 只更新 nixpkgs

# 清理旧版本
sudo nix-collect-garbage -d
```

**不需要单独运行 `home-manager switch`** —— Home Manager 已通过 NixOS 模块集成。

---

## 秘密管理 (sops-nix)

所有敏感信息（GitHub token、密码哈希）通过 sops-nix + age 加密管理。加密后的 `secrets/secrets.yaml` 可安全签入 git。部署时由主机 age 私钥自动解密到 `/run/secrets/`（tmpfs）。

### 添加新 secret

```bash
# 编辑并自动加密
sops secrets/secrets.yaml

# 在 modules/nixos/secrets.nix 中声明
# sops.secrets.新名字 = { ... };

# 在对应的 .nix 模块中引用
# config.sops.secrets.新名字.path

# 应用
sudo nixos-rebuild switch --flake .#wbb
```

### 更换主机 / 密钥泄露

1. 生成新的 age 密钥对：`age-keygen -o ~/.config/sops/age/keys.txt`
2. 更新 `.sops.yaml` 中的公钥
3. 重新加密：`sops updatekeys secrets/secrets.yaml`
4. `git commit` + `nixos-rebuild switch`

### 备份 age 私钥

私钥 (`AGE-SECRET-KEY-1...`) 是解密 secrets 的唯一凭据，丢失后无法恢复。请备份到密码管理器：

```bash
sudo cat /root/.config/sops/age/keys.txt
```

---

## 当前主机

| 主机名 | 用途 |
|--------|------|
| `wbb` | 主力桌面 |

---

## 目录结构

```
nixos-config/
├── flake.nix                       # Flakes 入口：inputs → nixosConfigurations.wbb
├── install.sh                      # 一键安装脚本
├── .sops.yaml                     # SOPS age 公钥加密规则
├── hosts/
│   └── wbb/                        # 主机 wbb
│       ├── configuration.nix       # 入口：导入硬件 + 系统模块 + Home Manager
│       ├── disks.nix               # disko 声明式分区布局
│       └── hardware-configuration.nix   # 由 install.sh 生成
├── modules/
│   ├── nixos/                      # 系统级模块
│   │   ├── default.nix             #   导入所有子系统模块
│   │   ├── bootloader.nix          #   systemd-boot (UEFI)
│   │   ├── boot.nix                #   btrfs / 休眠 / zram / initrd swapfile 偏移检测
│   │   ├── nix.nix                 #   Flakes / GC / 教育网镜像 / unfree 许可 / netrc
│   │   ├── secrets.nix             #   sops-nix 秘密声明（GitHub token + 密码）
│   │   ├── networking.nix          #   主机名 / NetworkManager / 防火墙
│   │   ├── locale.nix              #   时区 Asia/Shanghai / 中文 UTF-8
│   │   ├── ime.nix                 #   fcitx5 Wayland 协议支持
│   │   ├── users.nix               #   用户 wbb
│   │   ├── hardware.nix            #   VA-API 硬件加速 / 蓝牙
│   │   ├── sound.nix               #   PipeWire
│   │   ├── fonts.nix               #   中文字体 + Nerd Font 图标
│   │   ├── services.nix            #   SSH / 蓝牙 / 电源管理
│   │   ├── greetd.nix              #   greetd → niri-session
│   │   ├── snapper.nix             #   btrfs 自动快照
│   │   ├── desktop.nix             #   Niri 系统级 / xdg portal / 光标主题
│   │   └── packages.nix            #   系统级软件包
│   └── home/                       # Home Manager 用户级模块
│       ├── default.nix             #   入口
│       ├── niri/                   #   Niri 合成器 KDL 配置
│       └── programs/               #   用户程序（fish, kitty, neovim 等）
├── secrets/
│   └── secrets.yaml               # SOPS 加密的 secrets（可签入 git）
└── README.md
```

---

## 文件系统设计

由 [disko](https://github.com/nix-community/disko) 声明式管理（`hosts/wbb/disks.nix`）：

- **EFI**: 1G FAT32
- **btrfs**: label `nixos`
  - `@root` → `/` (compress=zstd:3, noatime)
  - `@nix` → `/nix` (compress=zstd:3, noatime)
  - `@persist` → `/persist` (Snapper 保护, compress=zstd:3, noatime)
  - `@swap` → `/swap` (swapfile 16G, 不压缩)
  - `@snapshots` → `/.snapshots`

`resume_offset` 由 initrd 脚本自动检测，换盘后重建即适配。

---

## 个性化要点

| 项目 | 值 |
|------|-----|
| 主机名 | `wbb` |
| 用户 | `wbb` |
| Shell | fish + starship |
| 登录管理 | greetd → niri-session |
| 合成器 | Niri (scrollable-tiling Wayland) |
| Shell 面板 | Noctalia v5 (面板/通知/启动器/锁屏/壁纸) |
| 输入法 | fcitx5 + 雾凇拼音 (rime-ice) |
| 终端 | Kitty (Catppuccin 主题) |
| 启动器 | Fuzzel |
| 休眠 | btrfs swapfile 16G + zramSwap 50% |
| 快照 | Snapper @persist (12h + 7d + 4w + 6m) |
| 时区 | Asia/Shanghai |
| Nix 镜像 | cernet 教育网镜像 + 官方 cache |

---

## 安全

- 所有敏感信息通过 **sops-nix + age** 加密签入 git，部署时主机密钥自动解密
- age 私钥仅存储在 `/root/.config/sops/age/keys.txt`（root 可读），永不进入 Nix store
- 换机器重装时需提供 age 私钥（手动或通过 install.sh）
