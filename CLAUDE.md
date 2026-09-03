# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概述

这是基于 **NixOS 26.05 Flakes** 的个人单主机桌面配置。合成器 **[Niri](https://github.com/YaLTeR/niri)** (scrollable-tiling Wayland compositor) + **[Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)** (面板/通知/启动器/锁屏,替代 waybar+mako+swaybg)。文件系统 btrfs 五子卷,由 `install.sh` 手工分区管理。

## 核心命令

```bash
# 构建并切换到当前配置(同时应用系统+Home Manager)
# 每次 switch 前自动硬件适配 (模块/hostPlatform/swapfile 大小/resume_offset, 见 scripts/adapt-hardware.sh)
./build.sh

# 仅构建、不切换(CI/验证; 硬件配置如需更新先跑 scripts/adapt-hardware.sh)
nixos-rebuild build --flake .#nixos

# 更新 flake inputs
nix flake update              # 更新所有
nix flake update nixpkgs      # 只更新 nixpkgs

# 全新安装(从 NixOS Live ISO)
sudo ./scripts/install.sh --disk /dev/sda    # 自动分区 + 硬件检测 + 安装
```

**不需要单独运行 `home-manager switch`** —— Home Manager 已通过 NixOS 模块 (`inputs.home-manager.nixosModules.home-manager`) 集成,`nixos-rebuild switch` 会同时应用用户配置。

## 架构

```
flake.nix                          # 入口: hostName/hostDir 定义 → nixosConfigurations.<hostName>
├── hosts/default/
│   ├── configuration.nix           # 主机定义: 导入所有子系统模块
│   ├── disks.nix                   # 声明式分区布局 (disko)
│   └── hardware-configuration.nix  # 硬件扫描结果: initrd/kernel 模块
├── modules/nixos/                  # 系统级模块(<nixpkgs/nixos/modules> 风格)
│   └── default.nix                 #   导入所有子系统模块(imports 列表)
├── modules/home/                   # Home Manager 用户级模块
│   └── default.nix                 #   入口, 导入 niri 配置 + 各 program
├── secrets/
│   ├── secrets.template.yaml      # 明文模板 (分发用)
│   └── secrets.yaml               # 本地初始化, 不入库 (gitignore)
├── scripts/
│   ├── install.sh                  # 全新安装流程 (disko + nixos-install; 统一入口在 Live 下转到此)
│   └── adapt-hardware.sh          # 硬件适配: 检测→重写硬件配置+swapfile (构建后还原)
├── build.sh                        # 统一入口: Live CD→install.sh, 已装→适配+switch
└── .sops.yaml                     # SOPS 加密规则 (声明用哪些 age 公钥)
```

**关键设计决策:**

- **纯 Wayland 环境** —— `services.xserver.enable = false`, 完全无 X11 支持。所有 GUI 程序必须原生支持 Wayland。
- **文件系统挂载由 [disko](https://github.com/nix-community/disko) 声明式管理** —— `nix run github:nix-community/disko -- --mode zap_create_mount` 在安装时一步完成分区/格式化/子卷/swapfile/挂载。配置入口 `hosts/default/disks.nix`, 生成的 `fileSystems`/`swapDevices` 由 `inputs.disko.nixosModules.disko` 模块注入。`hardware-configuration.nix` 只含 initrd/kernel 模块 (`nixos-generate-config` 生成部分), 文件系统不再手写, CPU 微码固定双开于 `modules/nixos/hardware.nix`。
- **分区通过 LABEL 寻址** —— ESP 分区 `-n ESP`, btrfs 根分区 `-L nixos`, 在 `disks.nix` 的 `extraArgs` 中设定, 跨重装稳定。
- **休眠 resume 使用 `by-label/nixos` + cmdline `resume_offset=`** —— 格式化时设 `-L nixos`,跨重装稳定; 内核恢复休眠镜像早于 initrd, 只认 cmdline。**休眠执行由 `hibernate-now` (sudoers 放行免密) 直写内核 `/sys/power/state` 走 S4, 每次休眠前动态探测偏移 (`btrfs inspect-internal map-swapfile`) 写入 `/sys/power/resume_offset`, 绕过 systemd 260 休眠栈** (260 + 内核 6.18 新挂载 API 下 btrfs swap 的 `CanHibernate` 恒为 "na", `systemctl hibernate` 被 logind 拒绝)。cmdline `resume_offset=` (boot.nix `boot.kernelParams`) 仓库常驻已知值 (最近一次探测或安装时固化, 探测失败时作为回退), **构建前由 `scripts/adapt-hardware.sh` 探测当前 swapfile 偏移注入 (build.sh 自动调用, 构建后 restore 还原), 与 swapfile 大小同机制** —— btrfs balance 移动 swapfile / 换盘重装后 rebuild 一次即自动同步, 无需手工查数。探测失败 (非 root 且 sudo 无缓存) 保留仓库回退值: `hibernate-now` 休眠前检测 cmdline 与实测不符时打印警告 (照常休眠), 提示 rebuild 同步。
- **登录用 greetd + tuigreet** —— 无显示管理器 (GDM/SDDM)。tuigreet 直接跑在 tty, 零 GUI 依赖 (nixpkgs 稳定包, 无额外 flake input), `greetd.nix` 用 `--remember` 记住上次用户、`--cmd niri-session` 固定会话; `greeter` 运行用户需在 `greetd.nix` 手动创建 (NixOS greetd 模块不自动建)。`greetd.nix` 设 `StartLimitBurst=20` + `KillMode=mixed` 防 greeter 崩溃重启触发 rate-limit 黑屏。
- **zramSwap 50%** + btrfs swapfile 双交换,满足休眠需求。swapfile 大小与内存等大 (`disks.nix` 的 `swap.swapfile.size`, 上取整; 休眠要求 swap ≥ 内存; **低内存安装期放宽至 8G** 留虚拟余量, 模板语义不受影响)。rebuild 时检测漂移并按方向分级处理: **内存变大 → 自动重建** (swap < RAM 休眠失效, 危险方向; swapoff 小内容回灌大内存安全), **内存变小 → 仅提示** (自动收缩 swapoff 大内容回灌小内存有 OOM 风险, 永不自动); 重建在本轮硬件适配之前, resume_offset 随适配探测同步修正。
- **`boot.initrd.systemd.enable = true`** —— systemd initrd 提供更干净的启动流程。
- **Wi-Fi 内核模块在 initrd 预加载** (install.sh 生成的 `hardware-configuration.nix` 或 fallback 模板),确保 NetworkManager 在启动早期就能管理无线。
- **NetworkManager 统一管理网络**, 不使用已废弃的 `networking.wireless.*`。
- **Snapper 仅保护 `@persist`** (不包括 `@swap`), 保留策略: 12 小时 + 7 天 + 4 周 + 6 月。
- **家目录持久化使用 [impermanence](https://github.com/nix-community/impermanence)** —— `modules/home/persist.nix` 用 `home.persistence."/persist".directories` 声明 (attr 名为持久化根路径, 不含家目录, 自动拼成 `/persist/home/<mainUser>/<dir>`), boot 期以 root bind mount `~/<dir>` <-> `/persist/home/<mainUser>/<dir>`, 对应用透明、早于登录生效。`.cc-switch` 特例保留 `modules/nixos/persist.nix` 手写 bind mount (需 nofail 兜底 + tmpfiles 预建); 该文件同时 mkForce `/` 与 `/persist` 的 `neededForBoot = true` (impermanence 断言要求, fstab 表现为 `x-initrd.mount`)。已有设备从旧 symlink 方案升级为一次性操作, 历史迁移脚本 `migrate-impermanence.sh` 已移除 (使命完成, 全新 install.sh 安装无此问题)。
- **`.gitignore` 使用白名单模式** —— `*` 拒绝一切, `!` 逐条放行 `.nix`/`.kdl`/`.sh`/`.lock`/`.md` 等。新增文件类型需在 `.gitignore` 中显式放行。
- **秘密管理使用 sops-nix + SSH host key** —— 敏感信息 (GitHub token、用户密码) 加密管理, 加密密钥为 SSH 主机密钥 (`.sops.yaml` 登记 `ssh-to-age` 转换的 host key 公钥)。部署时 sops-nix 自动用 host key 派生密钥解密到 `/run/secrets/` (tmpfs), 无需单独 age 密钥对。换主机时把新 host key 公钥加入 `.sops.yaml` 并 `sops updatekeys` 重新加密。
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
| `impermanence` (master) | 声明式持久化, 无 release tag 跟 master; 当前为 2024 重构后 API (HM 模块由 NixOS 模块经 `home-manager.sharedModules` 自动注入, `homeManagerModules` 输出已废弃; 目录一律 bind mount), 升级需留意 API 变化 |

## 秘密管理 (sops-nix)

**所有敏感信息通过 [sops-nix](https://github.com/Mic92/sops-nix) 管理:** 加密密钥使用 **SSH 主机密钥 (host key)** —— sops 原生兼容 SSH ed25519 (age 格式), `/etc/ssh/ssh_host_ed25519_key` 经 `ssh-to-age` 转换的 age 公钥登记在 `.sops.yaml`。部署时 sops-nix 自动用 host key 派生密钥解密到 `/run/secrets/` (tmpfs), **无需单独的 age 密钥对**。明文模板在 `secrets/secrets.template.yaml`, 真实 `secrets/secrets.yaml` 为 sops 加密密文, 可安全签入 git (commit/push 均可, `.gitignore` 白名单已放行 `*.yaml`; 修改后正常 commit, **绝不**提交未加密的明文)。

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

# 3. 加密后的 secrets.yaml 正常 commit 签入 (密文可安全入库), 直接应用
./build.sh
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

用上面的编辑命令 (ssh-to-age 派生 + SOPS_AGE_KEY_FILE) 打开 sops 编辑。secrets.yaml 为加密密文, 编辑后正常 commit; 注意只有 sops 编辑器写回的才是密文, **绝不**把解密后的明文内容提交进 git。

### Live CD 全新安装

`nixos-install` 阶段, sops-nix 从 host key 解密 secrets (`.sops.yaml` 需含该主机的 host key 公钥)。
install.sh 会在 `nixos-install` **前**把 Live CD 上 `/etc/ssh/ssh_host_ed25519_key` 自动固化到
目标系统 (`/mnt/etc/ssh/`, 首启时被 sshd 复用), 保证安装期与首启后的密钥一致。按是否有旧
host key 分两种场景:

**场景 A: 重装同机 / 换盘 (已有旧 host key, secrets 用它加密)**

先恢复旧 host key 到 Live CD 的 `/etc/ssh/`, 再安装 (install.sh 检测到后自动固化):

```bash
# 旧主机上备份 (含私钥与公钥, secrets 解密凭据)
sudo cat /etc/ssh/ssh_host_ed25519_key        # 保存私钥内容
sudo cat /etc/ssh/ssh_host_ed25519_key.pub    # 保存公钥内容
# Live CD 上写回 /etc/ssh/ (install.sh 从该路径读取固化)
sudo install -m600 -o root -g root <私钥>  /etc/ssh/ssh_host_ed25519_key
sudo install -m644 -o root -g root <公钥>  /etc/ssh/ssh_host_ed25519_key.pub
sudo ./scripts/install.sh --disk /dev/sda
```

安装期 sops 解密即成功 (无密钥警告), 重启后 `/run/secrets` 已就绪。

**场景 B: 首次全新安装 / 无 host key (分发接收者)**

install.sh 检测不到 host key 会跳过固化并警告, 安装期 sops 解密失败属预期:

```bash
sudo ./scripts/install.sh --disk /dev/sda
```

**安装后 (首次启动)**: 系统自动生成新 SSH host key, 按「首次设置」初始化 secrets (host key 公钥登记 `.sops.yaml` + 从模板加密 `secrets.yaml`), 再 `./build.sh` 应用。

### 换主机或密钥泄露

1. 新主机 `.sops.yaml` 登记自己的 host key 公钥: `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`
2. 旧 host key 派生密钥重新加密: `sops updatekeys secrets/secrets.yaml` (配合 `SOPS_AGE_KEY_FILE`)
3. `git commit` + `./build.sh`

### host key 变化处理 (重装 / 换设备)

host key 是解密 secrets 的凭据, 重装/换设备后 host key 变化会导致旧 secrets 无法解密。sops 支持**多 recipient**:

- **同设备重装**: 重装前备份 `/etc/ssh/ssh_host_ed25519_key*`, 恢复到 Live CD 的 `/etc/ssh/` 后跑 install.sh —— 脚本会在 `nixos-install` 前自动固化该 key (见上方「场景 A」), 首启后密钥不变且安装期即可解密 secrets。
- **更换设备**: 新设备 host key 公钥 (`ssh-to-age`) 加入 `.sops.yaml`, 旧设备用派生密钥 (`SOPS_AGE_KEY_FILE`) `sops updatekeys` 重新加密, commit+push 后新设备可解密。
- **建议**: `.sops.yaml` 保留备用 recipient, 避免单点丢失。
- **`.sops.yaml` 的 `age` 字段格式红线**: 值必须是「逗号分隔的 string」, 多 recipient 用 `>-` 折叠标量换行书写 (解析时换行折叠为空格)。写 YAML list 会报 `cannot unmarshal !!seq into string` 拒载 config —— 且 sops CLI 从密文件所在目录向上查找加载它, **加载失败连解密一起失败** (解密本身不使用 creation_rules, 但 config 解析优先; v3.8.1/v3.9.4 实测均拒绝)。详细操作注释见 `.sops.yaml` 文件头。
- **注意 sops 两套解密通道的差异**: sops-install-secrets (NixOS 安装/启动自动解密到 `/run/secrets`) 读 manifest 不读 `.sops.yaml`; sops CLI (`sops -d`/`-e`) 读 `.sops.yaml` —— "自动解密正常但 CLI 报 config 错误" 即此因。另: CLI 从密文件所在目录向上查找 config, 在无 `.sops.yaml` 的目录 (如 /tmp) 跑可绕开损坏的 config。

### GitHub token 失效 (401) 排查与轮换

**症状**: `nix flake update` (分支解析走 api.github.com) 报 HTTP error 401/403; 日常 rebuild 的 tarball 直链匿名下载不受影响。

**根因**: `nix.nix` 配置 `netrc-file = /run/secrets/github-netrc` (由 systemd `github-netrc` 服务从 `github-username`/`github-token` 生成**三条目**: api.github.com + github.com + codeload.github.com), nix 的分支解析请求携带该凭据, PAT 过期/被撤销后 401。tarball 直链不带凭据, 故 rebuild 无感。

**诊断** (在目标主机):
```bash
sudo cat /run/secrets/github-netrc    # 查看当前凭据 (三条目: api.github.com / github.com / codeload.github.com, 由 systemd 服务生成)
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
       "[\"github-token\"]" "\"github_pat_XXX\""
     rm -f /tmp/age-priv.txt
   '
   ```
   若 `nix shell` 卡在 flake 解析, 先 `nix build nixpkgs#sops` 拿到 `/nix/store/<hash>-sops/bin/sops` 直接调用。
3. `git add secrets/secrets.yaml` && commit `secrets: 轮换 github-pat` && `git push origin main`。
4. `./build.sh` 验证 (无 401 即成功)。

**已知坑**:
- 远程默认 shell 是 fish, `$?` 要用 `$status`; 复杂命令用 `bash -c` 或 `ssh ... 'bash -s'`。
- `sops --extract` 在无 TTY 环境可能报 `User canceled operation` (sops 3.13 的 TTY 交互怪癖), 不影响 `sops set`; 用第 4 步 rebuild 端到端验证即可。
- `ssh` 断连不会中断已启动的 `nixos-rebuild`, 远程进程会独立完成 switch。

### 当前管理的 secrets

| Secret 名 | 用途 | 引用位置 |
|-----------|------|---------|
| `github-username` | GitHub 用户名 (systemd 生成 netrc 用) | `modules/nixos/secrets.nix` |
| `github-token` | GitHub PAT (systemd `github-netrc` 服务据此生成三条目 netrc) | `modules/nixos/secrets.nix` → `systemd.services.github-netrc` → `nix.nix` `netrc-file` |
| `git-user-name` | git 提交署名 (激活钩子生成 `~/.config/git/identity`, `programs.git.includes` 引用) | `modules/home/programs/git.nix` → `home.activation.git-identity` |
| `git-user-email` | git 提交邮箱 (同上; 建议 GitHub noreply 地址) | `modules/home/programs/git.nix` → `home.activation.git-identity` |
| `ssh-id-ed25519` | SSH 用户私钥 (YAML 块标量多行; 激活钩子再生 `~/.ssh/id_ed25519`, 重装/换机一份 secrets 恢复全部身份; 权威源语义, 手动换密钥需更新此字段) | `modules/home/programs/ssh.nix` → `home.activation.ssh-identity` |
| `ssh-id-ed25519-pub` | SSH 用户公钥 (同上, 再生 `~/.ssh/id_ed25519.pub`) | `modules/home/programs/ssh.nix` → `home.activation.ssh-identity` |
| `main-user-password` | 用户密码(明文, sops 加密; 激活时 `mkpasswd -m yescrypt` 派生哈希注入 `/etc/shadow`); 另作为 mihomo API secret 复用 | `modules/nixos/users.nix` → `hashedPasswordFile` (派生脚本 `main-user-password-hash`); `modules/nixos/mihomo.nix` → `activationScripts.mihomo-config` |
| `cc-switch-s3-access-key-id` | cc-switch S3 (Cloudflare R2) 凭据 | `modules/home/programs/cc-switch.nix` → `cc-switch-install.service` (用户级服务, owner=mainUser) |
| `cc-switch-s3-secret-access-key` | cc-switch S3 (Cloudflare R2) 凭据 | `modules/home/programs/cc-switch.nix` → `cc-switch-install.service` (用户级服务, owner=mainUser) |
| `cc-switch-s3-bucket` | cc-switch S3 桶名 (R2) | `modules/home/programs/cc-switch.nix` → `cc-switch-install.service` (用户级服务, owner=mainUser) |
| `cc-switch-s3-endpoint` | cc-switch S3 端点 (R2) | `modules/home/programs/cc-switch.nix` → `cc-switch-install.service` (用户级服务, owner=mainUser) |
| `mihomo-subscription-url` | mihomo 订阅 URL 列表 (YAML 块标量每行一条, 各生成一个 proxy-provider: provider1/...) | `modules/nixos/mihomo.nix` → `activationScripts.mihomo-config` |

**sops-nix 模块:** `modules/nixos/secrets.nix` —— 声明 `sops.secrets.<name>`, 定义每个 secret 的权限和目标路径。

## 已有 NixOS 系统使用 (非 install.sh)

已有系统接管分发模板的步骤:

0. **本机定制**: 编辑 `hosts/default/local.nix` (非机密, 已纳入版本控制; 分发模板含默认值, 接收者改为自己的 hostName/mainUser):
   ```nix
   { lib, ... }: { hostName = "wbb"; mainUser = lib.mkForce "alice"; }
   ```
1. 自定义用户名: 也可直接在 `hosts/default/configuration.nix` 中 `mainUser = lib.mkForce "<已有用户名>"` (覆盖默认 `user`)。
2. 自定义主机名 (可选): 改 `flake.nix` 的 `let hostName`; `hostDir` 独立, 无需改目录名。
3. 替换硬件配置: `nixos-generate-config --root /` 生成后 `cp` 到 `hosts/default/hardware-configuration.nix` (模板内为通用示例)。
4. 初始化 secrets: `cp secrets/secrets.template.yaml secrets/secrets.yaml` → 填 `main-user-password`/`github-username`/`github-token` → `sops -e -i`。
5. `sudo nixos-rebuild build --flake .#<hostName>` 验证 → `switch` 应用。

**注意**: `users.nix` 用 `hashedPasswordFile` + `users.mutableUsers = false` 声明式设置 mainUser/root 密码 —— secrets 存**明文**, 激活脚本 `main-user-password-hash` (`users.nix`) 在 `setupSecretsForUsers` 之后、`users` 段之前用 `mkpasswd -m yescrypt --stdin` 派生哈希到 `/run/main-user-password-hash`, 每次 rebuild 强制应用 (手动 `passwd` 改的会被覆盖)。**不要**改回 `passwordFile`: nixpkgs 26.05 起它是 `hashedPasswordFile` 的废弃别名, 喂明文会原样落 `/etc/shadow` 且锁死登录。家目录数据保留。用户名需与已有用户一致 (否则新建)。

## 修改配置的典型流程

1. 编辑对应的 `.nix` 模块文件
2. `./build.sh` (在仓库根目录; 先自动硬件适配再 switch)
3. 如果是新增用户级程序(如 fish/kitty/neovim 配置),编辑 `modules/home/programs/<name>.nix`,同样 rebuild

## 添加新主机

1. 新建 `hosts/<hostname>/` 目录,添加 `configuration.nix` 和 `disks.nix` (`hardware-configuration.nix` 由 scripts/adapt-hardware.sh 首次运行自动生成)

2. 在 `flake.nix` 顶部将 `let hostName = "<新主机名>"` 改为新主机名 (目录名需与之一致)

3. 可以复用 `modules/` 下的系统模块

## install.sh 约束

- **必须 root** (`[ "$(id -u)" = 0 ]`): 需要分区、格式化、挂载、`nixos-install`
- **必须 git 仓库** 且会修复 `.git/index` 属主不一致 (libgit2 安全检查)
- **内存 < 7.5G (7680M, 保守阈值) 时自动创建临时 zram swap** 防止编译 OOM
- **构建期硬件适配** —— install.sh 与 build.sh 前都会运行 `scripts/adapt-hardware.sh` (检测当前硬件 → 重写 `hardware-configuration.nix` 模块/hostPlatform + `disks.nix` swapfile 大小 + `modules/nixos/boot.nix` 的 resume_offset), 构建完成后 `restore_adapt` 还原这三个文件 (适配是构建期临时状态, 系统已固化; 仓库保持分发模板语义, 换硬件/加内存后 rebuild 自动适配)
- **分区由 disko 管理** —— install.sh 用 `nix run github:nix-community/disko -- --mode zap_create_mount` (master 最新版) 替代手工 parted/mkfs/btrfs
- **仓库自动就位** —— install.sh 完成后把 Live CD 上的仓库复制到 `/persist/home/<mainUser>/code/nixos-config` (含 .git, 属主给 mainUser, 日常使用无需再 clone); 目标已存在仓库时跳过不覆盖 (保护用户未 push 改动)
- **root 无密码** (`--no-root-password`), 登录凭据仅通过主用户 (`mainUser`) 管理
- **可选 `GITHUB_TOKEN` 环境变量** —— 安装期给 Live CD 的 nix 提供 GitHub 凭据: 脚本把 `access-tokens` 注入 `NIX_CONFIG` (分支解析与 tarball 均带 token), 作用于 disko 与 nixos-install 的全部拉取; 用 `sudo env GITHUB_TOKEN=... ./scripts/install.sh` 传入 (sudo 默认清空环境变量)。未显式传入时, 若 Live CD 已恢复旧 host key (`/etc/ssh/ssh_host_ed25519_key`) 且存在 secrets/secrets.yaml, 脚本自动派生 age 私钥解密 github-token (整文件 `sops -d` + sed 提取, 规避 `--extract` 无 TTY 挂起); 解密失败 (全新安装/网络差) 静默回退匿名

## hardware-configuration.nix

此文件由 `scripts/adapt-hardware.sh` 自动生成 (install.sh 安装时与 build.sh 每次 switch 前均调用): 检测当前硬件 (模块/hostPlatform/swapfile) 重写本文件与 disks.nix (另注入 modules/nixos/boot.nix 的 resume_offset), 构建完成后由 `restore_adapt` 还原 (配置已固化进系统, 仓库保持干净)。CPU 微码固定双开于 `modules/nixos/hardware.nix`, 不再生成。迁移到不同硬件时直接 rebuild 即自动适配 (无需手动合并)。

## 与安装方案的关系

`install.sh` 自动化安装流程:分区/格式化/子卷/swapfile 由 **disko 声明式**(`hosts/default/disks.nix`)完成,非手写脚本。

## 脚本安装工具(cc-switch / claude / codex)

这三个工具**不走 Nix 打包**(自带自更新机制),用官方 install.sh 装到 `~/.local/bin`,
由 `modules/home/programs/fish.nix` 的 `fish_add_path ~/.local/bin` 纳入 PATH。

| 工具 | 安装命令 | 用途 |
|------|---------|------|
| cc-switch | `curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh \| bash` | Claude Code 配置切换 + 用量查询 |
| claude | `curl -fsSL https://claude.ai/install.sh \| bash` | Claude Code CLI(native installer) |
| codex | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` | OpenAI Codex CLI(布局同 claude: `~/.codex/packages/standalone` 版本目录 + current 软链) |

**固化方式**:用户级 systemd oneshot 服务 (`systemd.user.services`):
`claude-install.service` / `cc-switch-install.service`(含 S3 云同步自动配置)/
`codex-install.service`(设 CODEX_NON_INTERACTIVE=true 适配无 TTY, PATH 补
gawk——官方脚本依赖 awk 而单元 PATH 没有)分别负责补装。linger 常驻的
user manager 开机即拉起, **无需登录**; NixOS 激活 (home-manager.nix 的
home-manager-restart) 每次 switch 跨实例 restart 触发重跑,
**缺失才补装** (已装秒退, 幂等)。新装机/重装后一条 `nixos-rebuild switch`
即可复现。

**持久化**:工具目录(`.local/bin`、`.local/share/claude`、`.codex`,含 codex 登录态)
已在 `modules/home/persist.nix` 声明,本机重装(@root 重建)后保留,服务不再触发下载;
换机/清 persist 后仍由服务自动补装。

> 下载超时兜底:外层 curl 限 ~60s,但 install.sh 内部资产下载无超时——网络差曾致
> 激活无限挂起、HM 单元 5m 超时、**整个 rebuild 失败**。服务内用 `timeout 120`
> 包裹安装管道,单工具最坏 2 分钟内放弃(不拖垮激活)。
> 代理:服务先探测本机 mihomo mix-port (`127.0.0.1:7890`, 1s 内放弃),通则导出
> `https_proxy/http_proxy` 再下载——直连不可达的环境(claude.ai/chatgpt.com 被墙)
> 也能装成功;无代理环境零影响。

> 注意:这些是脚本装的非声明式工具(自带自更新),换机重装时由用户级服务自动补装;
> 若需手动重装,用上表的 curl 命令即可。

## 敏感信息

**所有敏感信息已通过 sops-nix + age 加密管理 (见上方"秘密管理"章节)。** 以下信息不再以明文签入 git:

- GitHub token → `secrets/secrets.yaml` → `github-username`/`github-token` → systemd 生成 `/run/secrets/github-netrc`(三条目)
- 用户密码(明文) → `secrets/secrets.yaml` → `main-user-password` → 解密到 `/run/secrets-for-users/main-user-password` (激活时派生 yescrypt 哈希注入 `/etc/shadow`)

**换机器/密钥变化时:** 流程见上方「换主机或密钥泄露」与「host key 变化处理」。

## 代码审查与修复记录

2026-08-31 全仓 max 级审查 (10 角度 + 本机实测验证), 6 项 findings 全部修复:

| # | 问题 | 修复 | commit |
|---|------|------|--------|
| 1 | mihomo 控制 API 绑 0.0.0.0 (secret 复用登录密码, LAN 可访问 WebUI) | `external-controller` 写死 `127.0.0.1:9090`, `ss -tlnp` 实测确认 | `69e3572` |
| 2 | `_fzf_git_status` 对未暂存行 " M path" 提取出 "M path" → git fatal | 状态列后取子串 + 剥 git C 引用 (含空格路径) 引号 + 统一 `git diff HEAD` (未跟踪走 `--no-index /dev/null`); if 块内 `set -l` 是块级作用域, 修改变量须无 `-l` | `a0037b6` |
| 3 | `_fzf_files`/`_fzf_history` 插入未转义, 含空格/引号条目被重新分词破坏 | `string escape` / `--print0` + `string split0` 单参数回填 | `a0037b6` |
| 4 | 安装钩子 `-x` 判据遇超时打断留下的半截可执行文件 → 自愈永久失效 | `--version` 鸭子判据, 损坏先 `rm` 再全量重装 | `4be29ae` |
| 5 | 静态 `resume_offset` 在 btrfs balance / 重装后过期, 唤醒静默丢会话 | 构建期探测注入 boot.nix (根 sudo 或 `sudo -n`), 探测失败保留仓库回退值 + `hibernate-now` 休眠前告警 | `265ff95` |
| 6 | 规则集单 CDN (jsdelivr), 缓存空 + CDN 不可达时规则静默落空直落 MATCH,PROXY | 三 CDN (cdn/fastly/gcore) 激活期预拉 /persist 缓存, marker 24h 防重试轰炸 | `69e3572` |

同时落地的相关修复: rime 词库持久化中途迁移竞态 (fcitx5 运行时再生 yaml 挡住 bind,
activation 失败 exit 4) —— `persistMigrate` 激活钩子自动迁移 + 一次性手工收尾,
详见 modules/home/persist.nix 注释。
