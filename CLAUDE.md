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
│   └── hardware-configuration.nix  # 硬件扫描结果 (由 install.sh 生成, 非仓库文件)
├── modules/nixos/                  # 系统级模块(<nixpkgs/nixos/modules> 风格)
│   └── default.nix                 #   导入所有子系统模块(imports 列表)
├── modules/home/                   # Home Manager 用户级模块
│   └── default.nix                 #   入口, 导入 niri 配置 + 各 program
```

**关键设计决策:**

- **文件系统挂载由 install.sh 在安装时生成** (`nixos-generate-config --root /mnt` 或 fallback 模板),写入 `hosts/wbb/hardware-configuration.nix`。`hardware-configuration.nix` 包含内核模块/CPU 微码和 `fileSystems`/`swapDevices`。
- **休眠 resume 使用 `by-label/nixos`** 而非 UUID —— 格式化时设 `-L nixos`,跨重装稳定。`resume_offset` 由 initrd 脚本 (`boot.nix` 中的 `detect-resume-offset` 服务) 在启动时自动检测。
- **greetd 直接拉起 niri-session** —— 无显示管理器 (GDM/SDDM)。
- **zramSwap 50%** + btrfs swapfile 16G 双交换,满足休眠需求。
- **`boot.initrd.systemd.enable = true`** —— systemd initrd 提供更干净的启动流程,也能兜底发现 swapfile 物理偏移。
- **Wi-Fi 内核模块在 initrd 预加载** (install.sh 生成的 `hardware-configuration.nix` 或 fallback 模板),确保 NetworkManager 在启动早期就能管理无线。
- **NetworkManager 统一管理网络**, 不使用已废弃的 `networking.wireless.*`。

## 修改配置的典型流程

1. 编辑对应的 `.nix` 模块文件
2. `sudo nixos-rebuild switch --flake .#wbb` (在仓库根目录)
3. 如果是新增用户级程序(如 fish/kitty/neovim 配置),编辑 `modules/home/programs/<name>.nix`,同样 rebuild

## 添加新主机

1. 在 `hosts/` 下新建目录,添加 `configuration.nix` 和 `hardware-configuration.nix`
2. 在 `flake.nix` 的 `outputs` 中添加 `nixosConfigurations.<hostname> = ...`
3. 可以复用 `modules/` 下的系统模块

## hardaware-configuration.nix

此文件由 `install.sh` 调用 `nixos-generate-config --root /mnt` 自动生成,然后提取 initrd/kernel 模块和 CPU 微码重写。迁移到不同硬件时删除此文件重新运行 `install.sh`,或在目标机器上运行 `nixos-generate-config` 后手动合并。

## 与 install.md 的关系

`install.md` 是手工装机文档(parted / mkfs / btrfs 子卷 / swapfile),是本配置的设计参考。`install.sh` 自动化整个安装流程,将 install.md 的分区方案实现为可复用的脚本。

## 敏感信息

- `modules/nixos/users.nix` 包含密码哈希,生产环境建议改用 `sops-nix` 或 `agenix` 加密
