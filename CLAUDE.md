# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概述

这是基于 **NixOS 26.05 Flakes** 的个人单主机桌面配置。合成器 **[Niri](https://github.com/YaLTeR/niri)** (scrollable-tiling Wayland compositor) + **[Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)** (面板/通知/启动器/锁屏,替代 waybar+mako+swaybg)。文件系统 btrfs 五子卷,由 `install.sh` 手工分区管理。

## 核心命令

```bash
# 构建并切换到当前配置(同时应用系统+Home Manager)
sudo nixos-rebuild switch --flake .#wbb

# 仅构建、不切换(CI/验证)
nixos-rebuild build --flake .#wbb

# 更新 flake inputs
nix flake update              # 更新所有
nix flake update nixpkgs      # 只更新 nixpkgs

# 全新安装(从 NixOS Live ISO)
sudo ./install.sh --disk /dev/sda    # 自动分区 + 硬件检测 + 安装
```

**不需要单独运行 `home-manager switch`** —— Home Manager 已通过 NixOS 模块 (`inputs.home-manager.nixosModules.home-manager`) 集成,`nixos-rebuild switch` 会同时应用用户配置。

## 架构

```
flake.nix                          # 入口: inputs → nixosConfigurations.wbb
├── hosts/wbb/
│   ├── configuration.nix           # 主机定义: 导入所有子系统模块
│   ├── disks.nix                   # 声明式分区布局 (disko)
│   └── hardware-configuration.nix  # 硬件扫描结果: 内核模块 + CPU 微码
├── modules/nixos/                  # 系统级模块(<nixpkgs/nixos/modules> 风格)
│   └── default.nix                 #   导入所有子系统模块(imports 列表)
├── modules/home/                   # Home Manager 用户级模块
│   └── default.nix                 #   入口, 导入 niri 配置 + 各 program
├── secrets/
│   └── secrets.yaml               # SOPS 加密的 secrets (可签入 git)
└── .sops.yaml                     # SOPS 加密规则 (声明用哪些 age 公钥)
```

**关键设计决策:**

- **纯 Wayland 环境** —— `services.xserver.enable = false`, 完全无 X11 支持。所有 GUI 程序必须原生支持 Wayland。
- **文件系统挂载由 [disko](https://github.com/nix-community/disko) 声明式管理** —— `nix run github:nix-community/disko -- --mode zap_create_mount` 在安装时一步完成分区/格式化/子卷/swapfile/挂载。配置入口 `hosts/wbb/disks.nix`, 生成的 `fileSystems`/`swapDevices` 由 `inputs.disko.nixosModules.disko` 模块注入。`hardware-configuration.nix` 只含内核模块/CPU 微码(`nixos-generate-config` 生成部分), 文件系统部分不再手写。
- **分区通过 LABEL 寻址** —— ESP 分区 `-n ESP`, btrfs 根分区 `-L nixos`, 在 `disks.nix` 的 `extraArgs` 中设定, 跨重装稳定。
- **休眠 resume 使用 `by-label/nixos`** 而非 UUID —— 格式化时设 `-L nixos`,跨重装稳定。`resume_offset` 由 initrd 脚本 (`boot.nix` 中的 `detect-resume-offset` 服务) 在启动时自动检测: 挂载 `@swap` 子卷 → `btrfs inspect-internal map-swapfile` → 写入 `/sys/power/resume_offset`。此自定义服务因 `systemd-hibernate-resume` 刻意不引入 btrfs-progs 依赖而无法自动发现 btrfs swapfile 偏移 (上游 commit 477fc07d)。
- **greetd 直接拉起 niri-session** —— 无显示管理器 (GDM/SDDM)。`greetd.nix` 中调整了 `StartLimitBurst=20` 并用 `pkill -x niri` 清理残留进程, 解决 niri 不退出时 greetd 反复重启的死循环问题。
- **zramSwap 50%** + btrfs swapfile 16G 双交换,满足休眠需求。
- **`boot.initrd.systemd.enable = true`** —— systemd initrd 提供更干净的启动流程,也能兜底发现 swapfile 物理偏移。
- **Wi-Fi 内核模块在 initrd 预加载** (install.sh 生成的 `hardware-configuration.nix` 或 fallback 模板),确保 NetworkManager 在启动早期就能管理无线。
- **NetworkManager 统一管理网络**, 不使用已废弃的 `networking.wireless.*`。
- **Snapper 仅保护 `@persist`** (不包括 `@swap`), 保留策略: 12 小时 + 7 天 + 4 周 + 6 月。
- **`.gitignore` 使用白名单模式** —— `*` 拒绝一切, `!` 逐条放行 `.nix`/`.kdl`/`.sh`/`.lock`/`.md` 等。新增文件类型需在 `.gitignore` 中显式放行。
- **秘密管理使用 sops-nix + age** —— 敏感信息 (GitHub token、密码哈希) 加密签入 git (`secrets/secrets.yaml`), 部署时由主机 age 私钥自动解密到 `/run/secrets/` (tmpfs)。无明文泄露风险, 换主机时只需把新主机公钥加入 `.sops.yaml` 并重新加密一次。

## 实验性功能

以下配置依赖实验性或快速迭代的特性, 升级 nixpkgs/niri/noctalia 时需留意兼容性:

| 项目 | 说明 |
|------|------|
| `nix.settings.experimental-features = ["nix-command" "flakes"]` | Flakes 在文档上仍标记为实验性 |
| `boot.initrd.systemd.enable = true` | systemd initrd 可能与部分硬件/内核模块有兼容问题 |
| Niri compositor | 活跃开发中, 配置格式 (kdl) 可能随版本变化 |
| Noctalia Shell | 外部第三方项目 (v5), 迭代快速 |
| `debug.honor-xdg-activation-with-invalid-serial` | config.kdl 中的调试标志, 解决特定窗口激活问题 |
| `sops-nix` | 秘密管理, secrets 加密签入 git, 部署时主机 age 密钥解密 |

## 秘密管理 (sops-nix)

**所有敏感信息通过 [sops-nix](https://github.com/Mic92/sops-nix) 管理:** secrets 用 [age](https://age-encryption.org/) 公钥加密后签入 git (`secrets/secrets.yaml`), 部署时 sops-nix 模块自动用主机 age 私钥解密到 `/run/secrets/` (tmpfs)。

### age 密钥是什么？

age 是一对公私钥——公钥加密、私钥解密。对用户的感知就是 `~/.config/sops/age/keys.txt` 里的两行：

```
# created: 2025-01-01T00:00:00+08:00
# public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AGE-SECRET-KEY-1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

- **公钥** (`age1...`): 填入 `.sops.yaml`, 告诉 sops "用这个公钥加密 secrets"。公钥可以公开, 不敏感。
- **私钥** (`AGE-SECRET-KEY-1...`): 放在 `~/.config/sops/age/keys.txt`, 用于解密。**绝对不能泄露**, 等同于 root 密码。

### 首次设置 (已安装的系统)

```bash
# 1. 生成 age 密钥对
mkdir -p ~/.config/sops/age
nix shell nixpkgs#age --command age-keygen -o ~/.config/sops/age/keys.txt
# 输出: Public key: age1xxxxx  ← 记下公钥

# 2. 将公钥写入 .sops.yaml (creation_rules.age 列表)
# 编辑 .sops.yaml, 把 age1xxxxx 加入 age: 列表, 删掉占位符

# 3. 编辑 secrets 并加密
nix shell nixpkgs#sops --command sops secrets/secrets.yaml
# 填写实际的 GitHub token 和密码哈希, 保存退出 (sops 自动加密)

# 4. 提交加密后的 secrets
git add .sops.yaml secrets/secrets.yaml && git commit -m "secrets: 实际值加密"
```

### 已有主机添加新 secret

`sops secrets/secrets.yaml` → 编辑 → 保存退出 (自动加密) → `git commit`。

### Live CD 全新安装

`nixos-install` 阶段, sops-nix 从 `/tmp/sops-age-key` 读取 age 私钥解密 secrets。
`install.sh` 的 [0.5/3] 阶段会自动检测并引导用户提供密钥。

**准备工作 (在旧主机上):**

```bash
# 复制当前的 age 私钥
cat ~/.config/sops/age/keys.txt
# 复制 AGE-SECRET-KEY-1 开头的那一行
```

**安装时 (Live CD 上):**

```bash
# 方式 A: 安装前写入 /tmp/sops-age-key
echo "AGE-SECRET-KEY-1..." | sudo tee /tmp/sops-age-key
sudo chmod 600 /tmp/sops-age-key

# 方式 B: 从旧主机 scp
scp user@old-host:.config/sops/age/keys.txt /tmp/sops-age-key

# 方式 C: 运行时 prompts 交互粘贴
# install.sh 检测到没有密钥时会引导你粘贴

# 然后正常安装
sudo ./install.sh --disk /dev/sda
```

`install.sh` 会自动把密钥持久化到 `/mnt/root/.config/sops/age/keys.txt`, 重启后系统自动拥有解密能力。

### 换主机或密钥泄露

1. 生成新的 age 密钥对
2. 把新公钥填入 `.sops.yaml`, 旧公钥删除
3. 用旧私钥解密 → 新公钥重新加密: `sops updatekeys secrets/secrets.yaml`
4. `git commit` + `nixos-rebuild switch`

### 当前管理的 secrets

| Secret 名 | 用途 | 引用位置 |
|-----------|------|---------|
| `github-netrc` | GitHub token (提高 API 限速, 避免 403) | `modules/nixos/nix.nix` → `netrc-file` |
| `wbb-password-hash` | 用户密码哈希 | `modules/nixos/users.nix` → `hashedPasswordFile` |

**sops-nix 模块:** `modules/nixos/secrets.nix` —— 声明 `sops.secrets.<name>`, 定义每个 secret 的权限和目标路径。

## 修改配置的典型流程

1. 编辑对应的 `.nix` 模块文件
2. `sudo nixos-rebuild switch --flake .#wbb` (在仓库根目录)
3. 如果是新增用户级程序(如 fish/kitty/neovim 配置),编辑 `modules/home/programs/<name>.nix`,同样 rebuild

## 添加新主机

1. 在 `hosts/` 下新建目录,添加 `configuration.nix`、`hardware-configuration.nix` 和 `disks.nix`

2. 在 `flake.nix` 的 `outputs` 中添加 `nixosConfigurations.<hostname> = ...`
3. 可以复用 `modules/` 下的系统模块

## install.sh 约束

- **必须 root** (`[ "$(id -u)" = 0 ]`): 需要分区、格式化、挂载、`nixos-install`
- **必须 git 仓库** 且会修复 `.git/index` 属主不一致 (libgit2 安全检查)
- **内存 < 8G 时自动创建 zram swap** 防止编译 OOM
- **自动 `git commit` 生成的 `hardware-configuration.nix`** 纳入版本控制
- **分区由 disko 管理** —— `nix run github:nix-community/disko -- --mode zap_create_mount` 替代手工 parted/mkfs/btrfs
- **root 无密码** (`--no-root-password`), 登录凭据仅通过用户 `wbb` 管理

## hardware-configuration.nix

此文件由 `install.sh` 调用 `nixos-generate-config --root /mnt` 自动生成,然后提取 initrd/kernel 模块和 CPU 微码重写。迁移到不同硬件时删除此文件重新运行 `install.sh`,或在目标机器上运行 `nixos-generate-config` 后手动合并。

## 与 install.md 的关系

`install.md` 是手工装机文档(parted / mkfs / btrfs 子卷 / swapfile),是本配置的设计参考。`install.sh` 自动化整个安装流程,将 install.md 的分区方案实现为可复用的脚本。

## 敏感信息

**所有敏感信息已通过 sops-nix + age 加密管理 (见上方"秘密管理"章节)。** 以下信息不再以明文签入 git:

- GitHub token → `secrets/secrets.yaml` → `github-netrc` → 解密到 `/run/secrets/github-netrc`
- 用户密码哈希 → `secrets/secrets.yaml` → `wbb-password-hash` → 解密到 `/run/secrets/wbb-password-hash`

**换机器重装时:** 先在新主机生成 age 密钥, 把公钥加入 `.sops.yaml`, 用旧主机的私钥重新加密 secrets, 再 `git push`。
