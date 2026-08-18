# nixos-config

基于 **NixOS 26.05 Flakes** 的桌面配置（[Niri](https://github.com/YaLTeR/niri) + [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)，btrfs 五子卷由 [disko](https://github.com/nix-community/disko) 管理，secrets 用 [sops-nix](https://github.com/Mic92/sops-nix) + SSH host key 加密）。

按**两种使用场景**组织：全新安装 / 日常使用。用户名/主机名在 `hosts/default/local.nix` 定制，secrets 在 `secrets/`。

> **这是完整的可分发 NixOS 桌面方案**：fork 到你的账户、填好 secrets，一条 `install.sh` 即可装出同款桌面。开始前先完成下方「准备工作」（约 10 分钟）。

---

## 准备工作（开始前完成，约 10 分钟）

**准备 1 · Fork 本仓库**

在 GitHub 仓库页面右上角点 **Fork**，把整套配置复制到你自己的账户下。后续所有定制都推送到**你的 fork**，而不是本仓库：

- secrets 用你的 host key 加密，只有你的机器能解密——需要你自己的仓库来保存
- 日常升级（`nix flake update`）会改动 `flake.lock`，同样要推送回你的 fork

**准备 2 · 申请 GitHub token**

1. 打开 [GitHub Tokens](https://github.com/settings/tokens) → **Generate new token (classic)**
2. Note 填 `nixos`（随意）；Expiration 建议 `No expiration`（省心）或 90 天（到期后按场景二轮换）
3. 勾选 **`public_repo`**（只读公开仓库，足够提升 API 限额）
4. 点 **Generate token**，**立即复制** `ghp_` 开头的 token——关闭页面后不再显示

token 用在两处：

- **安装时（可选）**：`sudo env GITHUB_TOKEN=ghp_xxx ./install.sh ...`，避免 GitHub 匿名限流 403
- **装好后（必需）**：填入 secrets 的 `github-netrc` 字段，`nix flake update` 升级时认证

---

## 场景一：全新安装（Live ISO · install.sh）

> **适用**：新电脑或重装，从空盘安装 NixOS。
> **要求**：x86_64 主机、EFI 启动、建议内存 8G+（不足自动创建 zram）；**目标磁盘会被整盘清空**。
> **准备**：U 盘启动 NixOS 26.05 Live ISO，打开终端。
> `install.sh` 只做：分区 → 硬件检测 → `nixos-install`（并固化 host key）。

**第 1 步 · 克隆你的 fork（准备 1）**

```bash
git clone https://github.com/<你的GitHub用户名>/nixos-config.git ~/nixos-config
cd ~/nixos-config
```
> clone 失败先排查网络（Live ISO 需先连 Wi-Fi 或插网线）。

**第 2 步 · 准备 host key（secrets 解密凭据）**

- **重装/换盘（有备份 host key）**：把备份的 `ssh_host_ed25519_key*` 复制回 Live CD 的 `/etc/ssh/`，`install.sh` 会固化到新系统（保证 secrets 可解密）。
- **全新首装（无备份）**：Live CD 默认可能没有 host key，先生成它：
  ```bash
  sudo ssh-keygen -A
  ```
  > `install.sh` **仅在 Live CD 检测到 host key 时**固化；否则新系统首启自行生成（届时 secrets 需按新 host key 重新加密）。

**第 3 步 · 初始化 secrets（首次）**

```bash
# 3.1 登记 host key 公钥（把输出的 age1xxx 加入 .sops.yaml 的 age 列表，替换示例公钥）
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age -c ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub

# 3.2 从模板创建 secrets.yaml 并编辑填值（保存自动加密）
# 加密使用 .sops.yaml 登记的 recipients（3.1 已加入你的 host key）
# host key 私钥属 root: 需 sudo; vim 由 nix shell 提供
sudo nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#sops nixpkgs#ssh-to-age nixpkgs#vim -c sh -c '
    cp secrets/secrets.template.yaml secrets/secrets.yaml
    export SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key"
    sops --encrypt --in-place secrets/secrets.yaml
    EDITOR=vim sops secrets/secrets.yaml
  '
```
> sops 会打开 vim，填**全部字段**后保存（`:wq`）：
> - `main-user-password-hash`：你的登录密码哈希。生成：`nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#whois -c mkpasswd -m yescrypt`（输入两次密码）
> - `github-username` / `github-token`：准备 2 申请的 GitHub 用户名与 token（systemd github-netrc 服务据此生成三条目 netrc：api.github.com / github.com / codeload.github.com，供 flake update 认证，缺任一都会限流）
> - `cc-switch-s3-access-key-id` / `cc-switch-s3-secret-access-key`：Cloudflare R2 访问密钥
> - `cc-switch-s3-bucket`：R2 桶名（如 `xxx`）
> - `cc-switch-s3-endpoint`：R2 endpoint（`https://<账户ID>.r2.cloudflarestorage.com`）

**第 4 步 · 配置 local.nix（用户名 / 主机名）**

编辑 `hosts/default/local.nix`：

```nix
{ lib, ... }: {
  hostName = "wbb";                 # 主机名
  mainUser = lib.mkForce "wbb";     # 用户名 (覆盖模板默认 user)
  mihomo-ui = "zashboard";          # mihomo WebUI: metacubexd / yacd / zashboard
}
```

**第 5 步 · 安装**

```bash
# 使用准备 2 的 token，避免 GitHub 限流导致安装失败
sudo env GITHUB_TOKEN=ghp_xxx ./install.sh -d /dev/sda -f    # 换成你的目标磁盘（如 /dev/sdb）
```
> 不带 token 也可安装（`sudo ./install.sh -d /dev/sda`，匿名限流时建议带上，见准备 2）；`-f` 跳过磁盘确认，去掉则需输入 `yes`。安装耗时较长，耐心等待。

**第 6 步 · 重启**

```bash
reboot
```
> 新系统首次启动用固化的 host key 解密 secrets，用第 4 步的用户名 + 第 3 步的密码登录。

---

## 场景二：日常使用

> **适用**：已装好并切换成功的系统，日常维护。所有命令在目标机器终端执行。

**第 1 步 · 克隆你的 fork（首次在本机使用）**

```bash
git clone https://github.com/<你的GitHub用户名>/nixos-config.git ~/nixos-config
cd ~/nixos-config
```
> 之后日常更新前先 `git pull` 拉取远程最新改动。

**第 2 步 · 日常更新（改配置后应用）**

```bash
nix flake update                               # 升级 flake inputs 版本（可选，含 noctalia 等）
sudo nixos-rebuild switch --flake .#nixos    # 应用配置变更（改 .nix / local.nix 后）
sudo nix-collect-garbage --delete-old          # 清理旧系统配置（保留当前）
```
> 不需要单独 `home-manager switch`（已集成）。

**修改密码 / GitHub token（编辑 secrets）**

```bash
cd nixos-config
sudo nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age nixpkgs#sops nixpkgs#vim -c sh -c 'export SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key"; EDITOR=vim sops secrets/secrets.yaml'
```
> 打开编辑器改任意字段（登录密码、GitHub token 等），保存自动加密 → `sudo nixos-rebuild switch --flake .#nixos` 生效。
> GitHub token 失效（`nix flake update` 报 401/403；日常 rebuild 不受影响）时，改 `github-token` 字段即可（systemd github-netrc 服务会重新生成三条目 netrc）。新 token 在 [GitHub tokens](https://github.com/settings/tokens) 生成（勾 `public_repo`）。

**重装 / 换设备前备份 host key**（secrets 解密凭据）

```bash
sudo cp -a /etc/ssh/ssh_host_ed25519_key* /备份位置/
```
> 重装时把它复制回 Live CD 的 `/etc/ssh/`（见场景一第 2 步，install.sh 会固化）；换设备见下。

**更换设备（新设备接管 secrets）**

1. 新设备上把它的 host key 公钥加入 `.sops.yaml`（`ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`）
2. 在旧设备（能解密的主机）上重加密：

   ```bash
   SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key" nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#sops nixpkgs#ssh-to-age -c sops updatekeys secrets/secrets.yaml
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
│   ├── local.nix                   #   本机定制 (用户名/主机名, 非机密, 纳入版本控制)
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
  - `@snapshots` → `/persist/.snapshots`

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

**自定义用户名/主机名**：都在 `hosts/default/local.nix` 改（`mainUser` + `hostName`），无需改 `flake.nix`（输出名固定 `.#nixos`）。改后 `switch` 生效。`local.nix` 非机密、纳入版本控制（分发模板自带默认值）。

---

## 安全

- secrets 经 **sops-nix + SSH host key** 加密签入 git，部署时自动解密到 `/run/secrets/`（tmpfs）
- `secrets.yaml` 加密后可安全提交（无 host key 私钥无法解密）
