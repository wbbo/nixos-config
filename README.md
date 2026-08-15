# nixos-config

基于 **NixOS 26.05 Flakes** 的桌面配置（[Niri](https://github.com/YaLTeR/niri) + [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)，btrfs 五子卷由 [disko](https://github.com/nix-community/disko) 管理，secrets 用 [sops-nix](https://github.com/Mic92/sops-nix) + SSH host key 加密）。

按**两种使用场景**组织：全新安装 / 日常使用。用户名/主机名在 `hosts/default/local.nix` 定制，secrets 在 `secrets/`。

---

## 场景一：全新安装（Live ISO · install.sh）

> **适用**：新电脑或重装，从空盘安装 NixOS。
> **准备**：U 盘启动 NixOS 26.05 Live ISO，打开终端。
> `install.sh` 只做：分区 → 硬件检测 → `nixos-install`（并固化 host key）。

**第 1 步 · 确认联网**

```bash
ping -c 3 baidu.com
```
> 有响应即网络正常，继续。

**第 2 步 · 克隆仓库**

```bash
git clone https://github.com/<你的GitHub用户名>/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

**第 3 步 · 准备 host key（secrets 解密凭据）**

- **重装/换盘（有备份 host key）**：把备份的 `ssh_host_ed25519_key*` 复制回 Live CD 的 `/etc/ssh/`，`install.sh` 会固化到新系统（保证 secrets 可解密）。
- **全新首装（无备份）**：Live CD 默认可能没有 host key，先生成它：
  ```bash
  sudo ssh-keygen -A
  ```
  > `install.sh` **仅在 Live CD 检测到 host key 时**固化；否则新系统首启自行生成（届时 secrets 需按新 host key 重新加密）。

**第 4 步 · 初始化 secrets（首次）**

```bash
# 4.1 登记 host key 公钥（把输出的 age1xxx 加入 .sops.yaml 的 age 列表，替换示例公钥）
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age -c ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub

# 4.2 从模板创建 secrets.yaml 并编辑填值（保存自动加密）
# 加密使用 .sops.yaml 登记的 recipients（4.1 已加入你的 host key）
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#sops nixpkgs#ssh-to-age -c sh -c '
    cp secrets/secrets.template.yaml secrets/secrets.yaml
    export SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key"
    sops --encrypt --in-place secrets/secrets.yaml
    sops secrets/secrets.yaml
  '
```
> sops 会打开编辑器（nano），填**全部字段**后保存（Ctrl+O → Enter → Ctrl+X）：
> - `main-user-password-hash`：你的登录密码哈希。生成：`nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#whois -c mkpasswd -m yescrypt`（输入两次密码）
> - `github-netrc`：GitHub token。格式 `machine github.com login 用户名 password ghp_xxx`（[生成 token](https://github.com/settings/tokens)，勾 `public_repo`）
> - `cc-switch-s3-access-key-id` / `cc-switch-s3-secret-access-key`：Cloudflare R2 访问密钥
> - `cc-switch-s3-bucket`：R2 桶名（如 `wbo`）
> - `cc-switch-s3-endpoint`：R2 endpoint（`https://<账户ID>.r2.cloudflarestorage.com`）

**第 5 步 · 配置 local.nix（用户名 / 主机名）**

编辑 `hosts/default/local.nix`：

```nix
{ lib, ... }: {
  hostName = "wbb";               # 改成你的主机名
  mainUser = lib.mkForce "alice"; # 改成你的用户名
}
```

**第 6 步 · 安装**

```bash
sudo ./install.sh --disk /dev/sda    # 换成你的目标磁盘（如 /dev/sdb）
```
> 脚本会列出磁盘要求确认，输入 `yes` 后开始：分区 → 检测硬件 → 安装 → 固化 host key。耗时较长，耐心等待。
> 静默安装（跳过确认）：`sudo ./install.sh -d /dev/sda -f`

**第 7 步 · 重启**

```bash
reboot
```
> 新系统首次启动用固化的 host key 解密 secrets，用第 5 步的用户名 + 第 4 步的密码登录。

---

## 场景二：日常使用

> **适用**：已装好并切换成功的系统，日常维护。所有命令在目标机器终端执行。

**第 1 步 · 克隆仓库（首次在本机使用）**

```bash
git clone https://github.com/<你的GitHub用户名>/nixos-config.git ~/nixos-config
cd ~/nixos-config
```
> 之后日常更新前先 `git pull` 拉取远程最新改动。

**第 2 步 · 日常更新（改配置后应用）**

```bash
nix flake update                               # 更新 flake inputs（可选; 先 update 再 switch 才生效）
sudo nixos-rebuild switch --flake .#nixos    # 应用配置变更（改 .nix / local.nix 后）
sudo nix-collect-garbage --delete-old          # 清理旧系统配置（保留当前）
```
> 不需要单独 `home-manager switch`（已集成）。

**修改密码 / GitHub token（编辑 secrets）**

```bash
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age nixpkgs#sops -c sh -c '
  export SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key"
  sops secrets/secrets.yaml
'
```
> 打开编辑器改任意字段（登录密码、GitHub token 等），保存自动加密 → `sudo nixos-rebuild switch --flake .#nixos` 生效。
> GitHub token 失效（rebuild 报 401）时，改 `github-netrc` 字段里的 token 即可。新 token 在 [GitHub tokens](https://github.com/settings/tokens) 生成（勾 `public_repo`）。

**重装 / 换设备前备份 host key**（secrets 解密凭据）

```bash
sudo cp -a /etc/ssh/ssh_host_ed25519_key* /备份位置/
```
> 重装时把它复制回 Live CD 的 `/etc/ssh/`（见场景一步骤 3，install.sh 会固化）；换设备见下。

**更换设备（新设备接管 secrets）**

1. 新设备上把它的 host key 公钥加入 `.sops.yaml`（`ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`）
2. 在旧设备（能解密的主机）上重加密：

   ```bash
   SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key" \
     nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#sops nixpkgs#ssh-to-age -c \
     sops updatekeys secrets/secrets.yaml
   ```
   > 用**旧 host key** 派生（只有旧密钥能解密旧密文）。
3. `git commit && git push`，新设备 pull 后即可解密。

> **建议**：`.sops.yaml` 保留一个备用 recipient（如另一台设备的 host key），避免单点丢失。

---

## 目录结构

```
nixos-config/
├── flake.nix                       # Flakes 入口: hostName 固定 → nixosConfigurations.nixos
├── install.sh                      # 全新安装脚本 (disko + nixos-install, 固化 host key)
├── .sops.yaml                      # sops 规则 (host key 派生的 age 公钥)
├── hosts/default/                  # 默认主机 (分发模板)
│   ├── configuration.nix           #   入口: 硬件 + 系统模块 + Home Manager
│   ├── local.nix                   #   本机定制 (用户名/主机名, 勿提交)
│   ├── disks.nix                   #   disko 声明式分区布局
│   └── hardware-configuration.nix  #   由 install.sh 生成
├── modules/
│   ├── nixos/                      # 系统级模块 (main-user/networking/secrets/users/greetd/mihomo 等)
│   └── home/                       # Home Manager 用户级模块 (niri + programs)
└── secrets/
    ├── secrets.template.yaml       # 明文模板 (分发用)
    └── secrets.yaml                # sops 加密 secrets (可安全提交)
```

---

## 文件系统设计

由 [disko](https://github.com/nix-community/disko) 声明式管理（`hosts/default/disks.nix`）：

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
| 主机名 / 用户 | `nixos` / `user`（默认，可定制） |
| Shell | fish + starship |
| 登录管理 | greetd → niri-session |
| 合成器 / 面板 | Niri (scrollable-tiling) + Noctalia v5 |
| 输入法 | fcitx5 + 雾凇拼音 (rime-ice) |
| 终端 / 启动器 | Kitty (Catppuccin) / Fuzzel |
| 休眠 | btrfs swapfile 16G + zramSwap 50% |
| 快照 | Snapper @persist (12h + 7d + 4w + 6m) |
| 时区 / Nix 镜像 | Asia/Shanghai / cernet + 官方 |

**自定义用户名/主机名**：都在 `hosts/default/local.nix` 改（`mainUser` + `hostName`），无需改 `flake.nix`（输出名固定 `.#nixos`）。改后 `switch` 生效，勿提交 `local.nix`。

---

## 安全

- secrets 经 **sops-nix + SSH host key** 加密签入 git，部署时自动解密到 `/run/secrets/`（tmpfs）
- `secrets.yaml` 加密后可安全提交（无 host key 私钥无法解密）
