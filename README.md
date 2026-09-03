# nixos-config

基于 **NixOS 26.05 Flakes** 的桌面配置（[Niri](https://github.com/YaLTeR/niri) + [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)，btrfs 五子卷由 [disko](https://github.com/nix-community/disko) 管理，secrets 用 [sops-nix](https://github.com/Mic92/sops-nix) + SSH host key 加密）。

按**两个场景**组织：安装与日常使用（场景一）/ 重装与更换设备（场景二）。用户名/主机名在 `hosts/default/local.nix` 定制，secrets 在 `secrets/`。

> **这是完整的可分发 NixOS 桌面方案**：fork 到你的账户、填好 secrets，一条 `install.sh` 即可装出同款桌面。开始前先完成下方「准备工作」（约 10 分钟）。

---

## 准备工作（开始前完成，约 10 分钟）

**准备 1 · Fork 本仓库**

在 GitHub 仓库页面右上角点 **Fork**，把整套配置复制到你自己的账户下。后续所有定制都推送到**你的 fork**，而不是本仓库：

- secrets 用你的 host key 加密，只有你的机器能解密——需要你自己的仓库来保存
- 日常升级（`nix flake update`）会改动 `flake.lock`，同样要推送回你的 fork

**准备 2 · 申请 GitHub token**

1. 打开 [GitHub Tokens](https://github.com/settings/tokens)，两种类型二选一：

   - **classic**：**Generate new token (classic)** → 勾选 `public_repo`（只读公开仓库，足够提升 API 限额），最省事
   - **fine-grained**（可限定仓库范围与权限）：**Generate fine-grained token** → Repository access 选 *Public repositories (read-only)* → Permissions → Contents: **Read-only**

2. Note 填 `nixos`（随意）；Expiration 建议 `No expiration`（省心）或 90 天（到期后按下文「日常使用」轮换指引），两种类型逻辑一致
3. 点 **Generate token**，**立即复制** token——关闭页面后不再显示

token 用在两处（申请一份、填入 secrets 一次即可）：

| 场景 | 方式 | 说明 |
|------|------|------|
| **安装时（全新首装/重装，自动）** | 第 3 步填入 secrets 后，`install.sh` 自动解密 | 手动传 `GITHUB_TOKEN` 仅作备用（token 未填真值/换号试网络） |
| **装好后（常驻）** | 同一份 secrets 的 `github-username` + `github-token` 字段 | systemd 生成 netrc 三条目，`nix flake update` 升级时认证（日常 rebuild 不依赖 token） |

> **token 失效症状**：`nix flake update` 报 401/403（日常 rebuild 不受影响）。轮换：GitHub 生成新 token → 编辑 `secrets/secrets.yaml` 的 `github-token` 字段 → commit + rebuild。

---

## 场景一：安装与日常使用（Live ISO → 装好后的维护）

> **适用**：新电脑或重装，从空盘安装 NixOS，以及装好后的日常维护。
> **要求**：EFI 启动、建议内存 8G+（不足自动创建 zram）；**目标磁盘会被整盘清空**。
> **准备**：U 盘启动 NixOS 26.05 Live ISO，连好网络（Wi-Fi 或网线），打开终端。
>
> 安装脚本自动完成：分区格式化（disko）→ 硬件适配（内核模块/hostPlatform/swapfile 按内存）→ token 自动解密（第 3 步完成后）→ host key 固化 → `nixos-install`。你只需要跟着下面 6 步走，装好后看「日常使用」。

**第 1 步 · 克隆你的 fork（准备 1 的仓库）**

```bash
git clone https://github.com/<你的GitHub用户名>/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

> ✅ 检查：`ls` 能看到 `scripts/`、`hosts/`、`modules/` 等目录。clone 失败先排查网络。

**第 2 步 · 准备 host key（secrets 的解密凭据）**

按你的情况二选一：

- **重装/换盘（有备份）**——把备份的 key 写回 Live CD：
  ```bash
  sudo install -m600 <私钥文件路径> /etc/ssh/ssh_host_ed25519_key
  sudo install -m644 <公钥文件路径> /etc/ssh/ssh_host_ed25519_key.pub
  ```
- **全新首装（无备份）**——生成一对新的：
  ```bash
  sudo ssh-keygen -A
  ```

> ✅ 检查：`sudo ls /etc/ssh/ssh_host_ed25519_key*` 能看到两个文件。
> 重装时**必须用旧 key**（secrets 是用它加密的）；全新首装用新 key，secrets 在第 3 步用新 key 加密。

**第 3 步 · 初始化 secrets（唯一的"动脑"步骤）**

**3.1** 把 host key 公钥转换为 age 格式（输出一行 `age1...`，复制它）：

```bash
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age \
  -c ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
```

**3.2** 打开 `.sops.yaml`，把 `age:` 里的**示例公钥替换为**刚才复制的 `age1...`（多台设备用逗号分隔、换行书写），保存：

```bash
vim .sops.yaml

# 示例（>- 折叠标量：解析结果为逗号分隔的单个 string）
# creation_rules:
#   - path_regex: secrets/secrets\.yaml$
#     age: >-
#       age12wxr8medgg97ala9r6wnsauast8v7x6l29jcvcgk6hrv7vfzzdsqhtrytf,
#       age1xxxxx（新设备的 key）
```

> ⚠️ **格式红线**：`age:` 的值必须是**逗号分隔的 string**，**不能写成 YAML list**（`age:` 下用 `- key`）——sops 会报 `cannot unmarshal !!seq into string` 拒载 config，**连解密一起失败**。

**3.3** 从模板创建 secrets 并逐项填值（保存自动加密；host key 私钥属 root 所以用 sudo，vim 由 nix shell 提供）：

```bash
sudo nix --extra-experimental-features 'nix-command flakes' \
  shell nixpkgs#sops nixpkgs#ssh-to-age nixpkgs#vim -c sh -c '
    cp secrets/secrets.template.yaml secrets/secrets.yaml
    export SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key"
    sops --encrypt --in-place secrets/secrets.yaml
    EDITOR=vim sops secrets/secrets.yaml
  '
```

sops 会打开 vim，**逐项按文件内注释填写**后保存（`:wq`）。要点：

- `main-user-password`：登录密码**明文**（系统自动派生哈希，勿自己算）
- `github-username` / `github-token`：准备 2 的凭据
- 其余（cc-switch 云同步、mihomo 订阅）按注释填，暂不用可留占位

> ✅ 检查：`cat secrets/secrets.yaml` 显示 `ENC[AES256_GCM,...]` 密文即为成功。

**第 4 步 · 配置用户名 / 主机名 / mihomo WebUI**

```bash
# 一键替换把 `wbb` 换成你的用户名/主机名（主机名同步改为同名）
sed -i 's/wbb/<你的用户名>/g' hosts/default/local.nix
# 或者手动修改
vim hosts/default/local.nix

# 示例
# hostName = "wbb";                 # 主机名
# mainUser = lib.mkForce "wbb";     # 用户名 (覆盖模板默认 user)
# mihomo-ui = "zashboard";          # mihomo WebUI: metacubexd / yacd / zashboard

# 确认 hostName / mainUser 已是你要的
cat hosts/default/local.nix   
```

**第 5 步 · 安装（耐心等待，约 10-30 分钟）**

```bash
# 换成你的目标磁盘（如 /dev/sdb）
sudo ./scripts/install.sh -d /dev/sda -f
```

初始化 secrets 时填写的 `github-token` 会被脚本**自动解密**用于安装期拉取（全新首装与重装同样生效），**无需手动传参**。仅当 secrets 的 token 填了占位、或想换 token 试试网络时手动传：

```bash
sudo env GITHUB_TOKEN=ghp_xxx ./scripts/install.sh -d /dev/sda -f
```

- `-f` 跳过磁盘确认；去掉则需手动输入 `yes`
- 硬件适配全自动（内核模块 / 架构 / swapfile 大小按内存），全程无需改任何配置文件

> ✅ 检查：最后输出 `安装完成!` + `SSH host key 已固化到目标系统` 即成功。

**第 6 步 · 重启与首启验证**

```bash
reboot
```

拔掉 U 盘，用**第 4 步的用户名 + 第 3 步的密码**登录，然后跑一遍首启检查：

```bash
systemctl --failed          # 期望: 无 failed 单元 (个别网络类失败重试即可)
ls /run/secrets/            # 期望: github-token 等解密后的 secrets 都在
ls ~/code/nixos-config/     # 期望: 仓库已自动就位 (install.sh 复制), 无需 clone
```

之后日常更新见下方「日常使用」。

---

### 日常使用（装好后）

> **先记住一件事**：日常 90% 的操作就是一条命令——`./scripts/rebuild.sh`（改完任何配置后跑它，自动硬件适配 + 应用变更）。所有命令在目标机器终端执行。

**仓库**：install.sh 已自动就位（`~/code/nixos-config`，含 `.git`，可直接 pull/rebuild），**无需 clone**。仅当仓库缺失时（如从别的设备拷配置过来）才需要：

```bash
git clone https://github.com/<你的GitHub用户名>/nixos-config.git ~/code/nixos-config
cd ~/code/nixos-config
```

> ✅ 检查：`ls ~/code/nixos-config` 能看到 `scripts/`、`hosts/`、`modules/` 等目录。

**常用操作速查**

| 想做什么 | 怎么做 |
|------|------|
| 改了任何 `.nix` / `local.nix`，应用变更 | `./scripts/rebuild.sh` |
| 升级依赖（noctalia/nixpkgs 等版本） | `nix flake update` → `./scripts/rebuild.sh` |
| 加了内存 / 换了硬件 | 直接 `./scripts/rebuild.sh`（自动硬件适配） |
| 改密码 / 换 GitHub token | 编辑 secrets（见下）→ `./scripts/rebuild.sh` |
| 清理旧系统版本 | `sudo nix-collect-garbage --delete-old` |

> ✅ 检查：`./scripts/rebuild.sh` 结尾输出 `硬件适配文件已还原` 即成功（适配置是构建期临时状态，完成后自动还原，仓库保持干净）。
> 不需要单独 `home-manager switch`（已集成）。

**改密码 / GitHub token（编辑 secrets）**

```bash
sudo nix --extra-experimental-features 'nix-command flakes' \
  shell nixpkgs#ssh-to-age nixpkgs#sops nixpkgs#vim -c \
  sh -c 'export SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key"; EDITOR=vim sops secrets/secrets.yaml'
```

sops 会打开 vim：改 `main-user-password`（登录密码明文，系统自动派生哈希）或 `github-token` 等字段 → `:wq` 保存（自动加密）→ `./scripts/rebuild.sh` 生效。

> **GitHub token 失效**：症状是 `nix flake update` 报 401/403（日常 rebuild 不受影响）。换新 token（[GitHub tokens](https://github.com/settings/tokens)，勾 `public_repo`）→ 改 `github-token` 字段 → rebuild。

**出问题？一键回滚（NixOS 安全网）**

```bash
sudo nixos-rebuild switch --rollback      # 回到上一次正常的系统配置
```

或重启后在 GRUB 菜单选旧 generation 启动。回滚只回退系统配置，你的数据不受影响。

---

## 场景二：重装与更换设备

> **适用**：同机重装 / 换盘 / 迁移到新电脑。
> **核心**：host key 是 secrets 的解密凭据——重装/换设备前，**第一件事永远是备份它**；丢它 = 全部 secret 需重新录入。

**第 1 步 · 备份 host key（必做）**

```bash
sudo cp -a /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key.pub /备份位置/
```

> ✅ 检查：`ls /备份位置/` 能看到**私钥 + 公钥**两个文件。妥善保管（U 盘/密码管理器附件）。

---

### A · 同机重装 / 换盘（key 不变，最简单）

1. 备份 host key（第 1 步）
2. U 盘启动 Live ISO，克隆你的 fork（场景一第 1 步）
3. 把备份的 key 写回 Live CD：

   ```bash
   sudo install -m600 /备份位置/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
   sudo install -m644 /备份位置/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
   ```

4. 走场景一安装：第 2 步（key 已就绪可跳过）→ **第 3 步整体跳过**（`secrets.yaml` 已在仓库且旧 key 可解密）→ 第 4 步确认 local.nix → 第 5 步安装

> ✅ 检查：安装日志里 `sops-install-secrets: Imported ... age key` 的指纹与 `.sops.yaml` 一致，且无解密报错。首启后 host key 不变、secrets 原样可用。

---

### B · 换新电脑（新 key 接管 secrets）

1. 旧机备份 host key（第 1 步），新机 Live CD 生成新 key（`sudo ssh-keygen -A`）
2. 新机把**新 key 公钥**转为 age 格式（复制输出的 `age1...`）：

   ```bash
   nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age \
     -c ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
   ```

3. 编辑 `.sops.yaml`：`age:` 折叠块里**追加**新公钥（逗号分隔换行；旧的 key **保留**，重加密还需要它）
4. 在**旧设备**（能解密的那台）重加密 secrets：

   ```bash
   SOPS_AGE_KEY_CMD="ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key" \
     nix --extra-experimental-features 'nix-command flakes' \
     shell nixpkgs#sops nixpkgs#ssh-to-age -c sops updatekeys secrets/secrets.yaml
   ```

5. 旧设备 `git add secrets/secrets.yaml && git commit && git push`
6. 新设备 `git pull`，然后走场景一安装（第 3 步跳过——secrets 已含新 key 的密文）

> ✅ 检查：新机安装日志 sops 解密成功；首启后 `ls /run/secrets/` 内容齐全。

---

### 钥匙丢了？（没备份就重装了）

后果：全部 secrets 需重新录入（密码/token/订阅 URL）。恢复方式：按场景一第 3 步重新生成并重加密一遍即可，配置文件本身（`.nix`）不受影响。

> **建议**：`.sops.yaml` 的 `age:` 里保留一个**备用 recipient**（如另一台设备的 host key），避免单点丢失。

---

## 目录结构

```
nixos-config/
├── flake.nix                       # Flakes 入口: hostName 固定 → nixosConfigurations.nixos
├── scripts/
│   ├── install.sh                  # 全新安装脚本 (disko + nixos-install, 固化 host key)
│   ├── adapt-hardware.sh           # 硬件适配: 检测→重写硬件配置+swapfile (构建完成后还原)
│   └── rebuild.sh                  # 适配 + nixos-rebuild switch (日常更新用这个)
├── .sops.yaml                      # sops 规则 (host key 派生的 age 公钥)
├── hosts/default/                  # 默认主机 (分发模板)
│   ├── configuration.nix           #   入口: 硬件 + 系统模块 + Home Manager
│   ├── local.nix                   #   本机定制 (用户名/主机名, 非机密, 纳入版本控制)
│   ├── disks.nix                   #   disko 声明式分区布局 (swapfile 大小由适配脚本重写)
│   └── hardware-configuration.nix  #   由 scripts/adapt-hardware.sh 自动生成
├── modules/
│   ├── nixos/                      # 系统级模块 (main-user/networking/secrets/users/greetd/mihomo/flatpak 等)
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
  - `@swap` → `/swap` (swapfile 大小按内存自适应, 不压缩)
  - `@snapshots` → `/persist/.snapshots`

`resume_offset` 由 initrd 脚本自动检测，换盘后重建即适配。swapfile 大小由 `scripts/adapt-hardware.sh` 按内存重写为与内存等大（上取整；休眠要求 swap ≥ 内存；换内存后 rebuild 自动跟随）。

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
| 应用分发 | Flatpak + GNOME Software (Flathub) |
| 休眠 | btrfs swapfile (与内存等大, 自适应) + zramSwap 50% |
| 快照 | Snapper @persist (12h + 7d + 4w + 6m) |
| 时区 / Nix 镜像 | Asia/Shanghai / cernet + 官方 |

**自定义用户名/主机名**：都在 `hosts/default/local.nix` 改（`mainUser` + `hostName`），无需改 `flake.nix`（输出名固定 `.#nixos`）。改后 `switch` 生效。`local.nix` 非机密、纳入版本控制（分发模板自带默认值）。

---

## 安全

- secrets 经 **sops-nix + SSH host key** 加密签入 git，部署时自动解密到 `/run/secrets/`（tmpfs）
- `secrets.yaml` 加密后可安全提交（无 host key 私钥无法解密）
