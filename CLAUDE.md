# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概述

这是基于 **NixOS 26.05 Flakes** 的个人单主机桌面配置。合成器 **[Niri](https://github.com/YaLTeR/niri)** (scrollable-tiling Wayland compositor) + **[Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)** (面板/通知/启动器/锁屏,替代 waybar+mako+swaybg)。文件系统 btrfs 五子卷,由 `install.sh` 手工分区管理。

## 核心命令

```bash
# 构建并切换到当前配置(同时应用系统+Home Manager)
sudo nixos-rebuild switch --flake .#nixos

# 仅构建、不切换(CI/验证)
nixos-rebuild build --flake .#nixos

# 更新 flake inputs
nix flake update              # 更新所有
nix flake update nixpkgs      # 只更新 nixpkgs

# 全新安装(从 NixOS Live ISO)
sudo ./install.sh --disk /dev/sda    # 自动分区 + 硬件检测 + 安装
```

**不需要单独运行 `home-manager switch`** —— Home Manager 已通过 NixOS 模块 (`inputs.home-manager.nixosModules.home-manager`) 集成,`nixos-rebuild switch` 会同时应用用户配置。

## 架构

```
flake.nix                          # 入口: hostName/hostDir 定义 → nixosConfigurations.<hostName>
├── hosts/default/
│   ├── configuration.nix           # 主机定义: 导入所有子系统模块
│   ├── disks.nix                   # 声明式分区布局 (disko)
│   └── hardware-configuration.nix  # 硬件扫描结果: 内核模块 + CPU 微码
├── modules/nixos/                  # 系统级模块(<nixpkgs/nixos/modules> 风格)
│   └── default.nix                 #   导入所有子系统模块(imports 列表)
├── modules/home/                   # Home Manager 用户级模块
│   └── default.nix                 #   入口, 导入 niri 配置 + 各 program
├── secrets/
│   ├── secrets.template.yaml      # 明文模板 (分发用)
│   └── secrets.yaml               # 本地初始化, 不入库 (gitignore)
└── .sops.yaml                     # SOPS 加密规则 (声明用哪些 age 公钥)
```

**关键设计决策:**

- **纯 Wayland 环境** —— `services.xserver.enable = false`, 完全无 X11 支持。所有 GUI 程序必须原生支持 Wayland。
- **文件系统挂载由 [disko](https://github.com/nix-community/disko) 声明式管理** —— `nix run github:nix-community/disko -- --mode zap_create_mount` 在安装时一步完成分区/格式化/子卷/swapfile/挂载。配置入口 `hosts/default/disks.nix`, 生成的 `fileSystems`/`swapDevices` 由 `inputs.disko.nixosModules.disko` 模块注入。`hardware-configuration.nix` 只含内核模块/CPU 微码(`nixos-generate-config` 生成部分), 文件系统部分不再手写。
- **分区通过 LABEL 寻址** —— ESP 分区 `-n ESP`, btrfs 根分区 `-L nixos`, 在 `disks.nix` 的 `extraArgs` 中设定, 跨重装稳定。
- **休眠 resume 使用 `by-label/nixos`** 而非 UUID —— 格式化时设 `-L nixos`,跨重装稳定。`resume_offset` 由 initrd 脚本 (`boot.nix` 中的 `detect-resume-offset` 服务) 在启动时自动检测: 挂载 `@swap` 子卷 → `btrfs inspect-internal map-swapfile` → 写入 `/sys/power/resume_offset`。此自定义服务因 `systemd-hibernate-resume` 刻意不引入 btrfs-progs 依赖而无法自动发现 btrfs swapfile 偏移 (上游 commit 477fc07d)。
- **greetd 直接拉起 niri-session** —— 无显示管理器 (GDM/SDDM)。`greetd.nix` 中调整了 `StartLimitBurst=20` 并用 `pkill -x niri` 清理残留进程, 解决 niri 不退出时 greetd 反复重启的死循环问题。
- **zramSwap 50%** + btrfs swapfile 16G 双交换,满足休眠需求。
- **`boot.initrd.systemd.enable = true`** —— systemd initrd 提供更干净的启动流程,也能兜底发现 swapfile 物理偏移。
- **Wi-Fi 内核模块在 initrd 预加载** (install.sh 生成的 `hardware-configuration.nix` 或 fallback 模板),确保 NetworkManager 在启动早期就能管理无线。
- **NetworkManager 统一管理网络**, 不使用已废弃的 `networking.wireless.*`。
- **Snapper 仅保护 `@persist`** (不包括 `@swap`), 保留策略: 12 小时 + 7 天 + 4 周 + 6 月。
- **`.gitignore` 使用白名单模式** —— `*` 拒绝一切, `!` 逐条放行 `.nix`/`.kdl`/`.sh`/`.lock`/`.md` 等。新增文件类型需在 `.gitignore` 中显式放行。
- **秘密管理使用 sops-nix + SSH host key** —— 敏感信息 (GitHub token、密码哈希) 加密管理, 加密密钥为 SSH 主机密钥 (`.sops.yaml` 登记 `ssh-to-age` 转换的 host key 公钥)。部署时 sops-nix 自动用 host key 派生密钥解密到 `/run/secrets/` (tmpfs), 无需单独 age 密钥对。换主机时把新 host key 公钥加入 `.sops.yaml` 并 `sops updatekeys` 重新加密。
- **主用户名与主机名参数化** —— `options.mainUser` (`modules/nixos/main-user.nix`, 默认 `user`) 是唯一用户名硬编码点, NixOS 层引用 `config.mainUser` (users/greetd/home-manager key), Home Manager 层经 `extraSpecialArgs` 以 `mainUser` 参数传入 (`modules/home/*`)。主机名在 `flake.nix` 的 `let hostName = "nixos"` 定义 (`networking.hostName`、flake 输出 `nixosConfigurations.${hostName}`), 物理目录 `let hostDir = "default"` (`hosts/${hostDir}/`), 二者解耦。install.sh 自动从 flake.nix 读取主机名/主机目录, 用户名/主机名可在 `hosts/<hostDir>/local.nix` 覆盖。分发模板默认值均为中性占位, 接收者自行定制。

## 实验性功能

以下配置依赖实验性或快速迭代的特性, 升级 nixpkgs/niri/noctalia 时需留意兼容性:

| 项目 | 说明 |
|------|------|
| `nix.settings.experimental-features = ["nix-command" "flakes"]` | Flakes 在文档上仍标记为实验性 |
| `boot.initrd.systemd.enable = true` | systemd initrd 可能与部分硬件/内核模块有兼容问题 |
| Niri compositor | 活跃开发中, 配置格式 (kdl) 可能随版本变化 |
| Noctalia Shell | 外部第三方项目 (v5), 迭代快速 |
| `debug.honor-xdg-activation-with-invalid-serial` | config.kdl 中的调试标志, 解决特定窗口激活问题 |
| `sops-nix` | 秘密管理, secrets 加密签入 git, 部署时 SSH host key 派生密钥解密 |

## 秘密管理 (sops-nix)

**所有敏感信息通过 [sops-nix](https://github.com/Mic92/sops-nix) 管理:** 加密密钥使用 **SSH 主机密钥 (host key)** —— sops 原生兼容 SSH ed25519 (age 格式), `/etc/ssh/ssh_host_ed25519_key` 经 `ssh-to-age` 转换的 age 公钥登记在 `.sops.yaml`。部署时 sops-nix 自动用 host key 派生密钥解密到 `/run/secrets/` (tmpfs), **无需单独的 age 密钥对**。明文模板在 `secrets/secrets.template.yaml`, 真实 `secrets/secrets.yaml` 需保持 git 可见 (git add -f 进 index, 勿 commit)。

### host key 与 sops 的关系

- **公钥**: `/etc/ssh/ssh_host_ed25519_key.pub` → `ssh-to-age -i` 转换 → age 公钥 (`age1...`) → 填入 `.sops.yaml`
- **私钥**: `/etc/ssh/ssh_host_ed25519_key` → `ssh-to-age -private-key -i` 派生 age 私钥 → 解密 secrets
- sops-nix 部署时自动扫描 host key 派生密钥, 无需额外配置

### 首次设置 (已安装的系统) / 分发接收者初始化

```bash
# 1. 登记 host key 公钥到 .sops.yaml
nix shell nixpkgs#ssh-to-age -c ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
# → age1xxx (加入 .sops.yaml 的 age 列表)

# 2. 从模板创建并加密 (用 .sops.yaml 的 host key 公钥)
cp secrets/secrets.template.yaml secrets/secrets.yaml
nix shell nixpkgs#sops -c sops -e -i secrets/secrets.yaml

# 3. secrets.yaml 保持 git 可见 (git add -f, 勿 commit), 直接应用
sudo nixos-rebuild switch --flake .#nixos
```

### 编辑 secrets (sops CLI 需 host key 派生密钥)

sops CLI 不会自动找 host key, 需派生 age 私钥 + `SOPS_AGE_KEY_FILE`:

```bash
nix shell nixpkgs#sops nixpkgs#ssh-to-age nixpkgs#nano -c sh -c '
  export EDITOR=nano
  ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /tmp/age-priv.txt
  chmod 600 /tmp/age-priv.txt
  SOPS_AGE_KEY_FILE=/tmp/age-priv.txt sops secrets/secrets.yaml
  rm -f /tmp/age-priv.txt
'
```

> sops-nix 部署时自动用 host key 解密 (无需环境变量); 仅 sops CLI 编辑/解密需要派生步骤。

### 已有主机添加新 secret

用上面的编辑命令 (ssh-to-age 派生 + SOPS_AGE_KEY_FILE) 打开 sops 编辑。**不要提交** `secrets/secrets.yaml` 的真实值。

### Live CD 全新安装

`nixos-install` 阶段, sops-nix 从 host key 解密 secrets (`.sops.yaml` 需含该主机的 host key 公钥)。

**准备工作 (在旧主机上):**

```bash
# 备份 host key 私钥 (secrets 解密凭据)
sudo cat /etc/ssh/ssh_host_ed25519_key
```

**安装时 (Live CD 上):**

```bash
# install.sh 只做分区 + 硬件检测 + 安装, 无需准备密钥
sudo ./install.sh --disk /dev/sda
```

**安装后 (首次启动)**: 系统自动生成 SSH host key, 按「首次设置」初始化 secrets (host key 公钥登记 `.sops.yaml` + 从模板加密 `secrets.yaml`), 再 `nixos-rebuild switch` 应用。

### 换主机或密钥泄露

1. 新主机 `.sops.yaml` 登记自己的 host key 公钥: `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`
2. 旧 host key 派生密钥重新加密: `sops updatekeys secrets/secrets.yaml` (配合 `SOPS_AGE_KEY_FILE`)
3. `git commit` + `nixos-rebuild switch`

### host key 变化处理 (重装 / 换设备)

host key 是解密 secrets 的凭据, 重装/换设备后 host key 变化会导致旧 secrets 无法解密。sops 支持**多 recipient**:

- **同设备重装**: 重装前备份 `/etc/ssh/ssh_host_ed25519_key*`, 重装后写回并 `systemctl restart sshd`, host key 保持不变。
- **更换设备**: 新设备 host key 公钥 (`ssh-to-age`) 加入 `.sops.yaml`, 旧设备用派生密钥 (`SOPS_AGE_KEY_FILE`) `sops updatekeys` 重新加密, commit+push 后新设备可解密。
- **建议**: `.sops.yaml` 保留备用 recipient, 避免单点丢失。

### GitHub token 失效 (401) 排查与轮换

**症状**: `nix flake update` (分支解析走 api.github.com) 报 HTTP error 401/403; 日常 rebuild 的 tarball 直链匿名下载不受影响。

**根因**: `modules/nixos/nix.nix` 配置 `netrc-file = /run/secrets/github-netrc` (仅 `api.github.com` 条目), nix 的分支解析请求携带该凭据, PAT 过期/被撤销后 401。tarball 直链不带凭据, 故 rebuild 无感。

**诊断** (在目标主机):
```bash
sudo cat /run/secrets/github-netrc    # 查看当前凭据: machine api.github.com login <user> password <token>
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer <token>" \
  https://api.github.com/user                        # 401 = token 失效
curl -s -o /dev/null -w "%{http_code}\n" -L \
  https://github.com/nix-community/disko/archive/<rev>.tar.gz   # 200/302 = 网络正常
NIX_CONFIG='netrc-file = /dev/null' nix flake update noctalia   # 临时匿名, 验证根因; 还原: git checkout flake.lock
```

**轮换步骤**:
1. GitHub 生成新 PAT: classic 勾选 `public_repo` (限速提升足够); 若要 push 仓库再加 `Contents: Read and write`。
2. 更新 `secrets/secrets.yaml` —— `sops set` 需 host key 派生密钥 (`SOPS_AGE_KEY_FILE`), value 必须是 **JSON 字符串** (外层带引号):
   ```bash
   cd ~/code/nixos-config
   nix shell nixpkgs#sops nixpkgs#ssh-to-age -c sh -c '
     ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /tmp/age-priv.txt
     chmod 600 /tmp/age-priv.txt
     SOPS_AGE_KEY_FILE=/tmp/age-priv.txt sops set secrets/secrets.yaml \
       "[\"github-netrc\"]" "\"machine api.github.com login <你的GitHub用户名> password github_pat_XXX\""
     rm -f /tmp/age-priv.txt
   '
   ```
   若 `nix shell` 卡在 flake 解析, 先 `nix build nixpkgs#sops` 拿到 `/nix/store/<hash>-sops/bin/sops` 直接调用。
3. `git add secrets/secrets.yaml` && commit `secrets: 轮换 github-pat` && `git push origin main`。
4. `sudo nixos-rebuild switch --flake .#nixos` 验证 (无 401 即成功)。

**已知坑**:
- 远程默认 shell 是 fish, `$?` 要用 `$status`; 复杂命令用 `bash -c` 或 `ssh ... 'bash -s'`。
- `sops --extract` 在无 TTY 环境可能报 `User canceled operation` (sops 3.13 的 TTY 交互怪癖), 不影响 `sops set`; 用第 4 步 rebuild 端到端验证即可。
- `ssh` 断连不会中断已启动的 `nixos-rebuild`, 远程进程会独立完成 switch。

### 当前管理的 secrets

| Secret 名 | 用途 | 引用位置 |
|-----------|------|---------|
| `github-netrc` | GitHub token netrc (仅 `api.github.com` 条目: flake update 分支解析认证; tarball 匿名) | `modules/nixos/nix.nix` → `netrc-file` |
| `main-user-password-hash` | 用户密码哈希 | `modules/nixos/users.nix` → `hashedPasswordFile` |

**sops-nix 模块:** `modules/nixos/secrets.nix` —— 声明 `sops.secrets.<name>`, 定义每个 secret 的权限和目标路径。

## 已有 NixOS 系统使用 (非 install.sh)

已有系统接管分发模板的步骤:

0. **本机定制** (推荐): 创建 gitignored 的 `hosts/default/local.nix`, 覆盖 `hostName`/`mainUser` (类似 secrets 的本地化, 不入库):
   ```nix
   { lib, ... }: { hostName = "wbb"; mainUser = lib.mkForce "alice"; }
   ```
1. 自定义用户名: 也可直接在 `hosts/default/configuration.nix` 中 `mainUser = lib.mkForce "<已有用户名>"` (覆盖默认 `user`)。
2. 自定义主机名 (可选): 改 `flake.nix` 的 `let hostName`; `hostDir` 独立, 无需改目录名。
3. 替换硬件配置: `nixos-generate-config --root /` 生成后 `cp` 到 `hosts/default/hardware-configuration.nix` (模板内为通用示例)。
4. 初始化 secrets: `cp secrets/secrets.template.yaml secrets/secrets.yaml` → 填 `main-user-password-hash`/`github-netrc` → `sops -e -i`。
5. `sudo nixos-rebuild build --flake .#<hostName>` 验证 → `switch` 应用。

**注意**: `users.nix` 用 `hashedPasswordFile` 设置 mainUser 密码, 会覆盖已有用户密码为 secrets 哈希; 家目录数据保留。用户名需与已有用户一致 (否则新建)。

## 修改配置的典型流程

1. 编辑对应的 `.nix` 模块文件
2. `sudo nixos-rebuild switch --flake .#nixos` (在仓库根目录)
3. 如果是新增用户级程序(如 fish/kitty/neovim 配置),编辑 `modules/home/programs/<name>.nix`,同样 rebuild

## 添加新主机

1. 新建 `hosts/<hostname>/` 目录,添加 `configuration.nix` 和 `disks.nix` (`hardware-configuration.nix` 由 install.sh 生成)

2. 在 `flake.nix` 顶部将 `let hostName = "<新主机名>"` 改为新主机名 (目录名需与之一致)

3. 可以复用 `modules/` 下的系统模块

## install.sh 约束

- **必须 root** (`[ "$(id -u)" = 0 ]`): 需要分区、格式化、挂载、`nixos-install`
- **必须 git 仓库** 且会修复 `.git/index` 属主不一致 (libgit2 安全检查)
- **内存 < 8G 时自动创建 zram swap** 防止编译 OOM
- **自动 `git commit` 生成的 `hardware-configuration.nix`** 纳入版本控制
- **分区由 disko 管理** —— install.sh 用 `nix run github:nix-community/disko -- --mode zap_create_mount` (master 最新版) 替代手工 parted/mkfs/btrfs
- **root 无密码** (`--no-root-password`), 登录凭据仅通过主用户 (`mainUser`) 管理
- **可选 `GITHUB_TOKEN` 环境变量** —— 安装期给 Live CD 的 nix 提供 GitHub 凭据: 脚本把 `access-tokens` 注入 `NIX_CONFIG` (分支解析与 tarball 均带 token), 作用于 disko 与 nixos-install 的全部拉取; 用 `sudo env GITHUB_TOKEN=... ./install.sh` 传入 (sudo 默认清空环境变量)

## hardware-configuration.nix

此文件由 `install.sh` 调用 `nixos-generate-config --root /mnt` 自动生成,然后提取 initrd/kernel 模块和 CPU 微码重写。迁移到不同硬件时删除此文件重新运行 `install.sh`,或在目标机器上运行 `nixos-generate-config` 后手动合并。

## 与 install.md 的关系

`install.md` 是手工装机文档(parted / mkfs / btrfs 子卷 / swapfile),是本配置的设计参考。`install.sh` 自动化整个安装流程,将 install.md 的分区方案实现为可复用的脚本。

## 脚本安装工具(cc-switch / claude)

这两个工具**不走 Nix 打包**(自带自更新机制),用官方 install.sh 装到 `~/.local/bin`,
由 `modules/home/programs/fish.nix` 的 `fish_add_path ~/.local/bin` 纳入 PATH。

| 工具 | 安装命令 | 用途 |
|------|---------|------|
| cc-switch | `curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh \| bash` | Claude Code 配置切换 + 用量查询 |
| claude | `curl -fsSL https://claude.ai/install.sh \| bash` | Claude Code CLI(native installer) |

**固化方式**:`modules/home/programs/cc-switch-claude.nix` 提供 home-manager 激活钩子
(`home.activation.installScriptTools`),每次 switch 时检查 `~/.local/bin` 里两个工具是否缺失,
**缺失才补装**(失败不阻断 switch)。新装机/重装后一条 `nixos-rebuild switch` 即可复现。

> 注意:这两个是脚本装的非声明式工具(自带自更新),换机重装时由激活钩子自动补装;
> 若需手动重装,用上面的 curl 命令即可。

## 敏感信息

**所有敏感信息已通过 sops-nix + age 加密管理 (见上方"秘密管理"章节)。** 以下信息不再以明文签入 git:

- GitHub token → `secrets/secrets.yaml` → `github-netrc` → 解密到 `/run/secrets/github-netrc`
- 用户密码哈希 → `secrets/secrets.yaml` → `main-user-password-hash` → 解密到 `/run/secrets/main-user-password-hash`

**换机器/密钥变化时:** 流程见上方「换主机或密钥泄露」与「host key 变化处理」。
