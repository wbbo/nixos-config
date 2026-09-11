# 无桌面 NixOS 安装教程（手工分区 + flake）

适用场景：服务器、软路由、VM、无 GUI 的小主机。全程 CLI，装完通过 SSH 管理。
桌面环境不在本文范围（本仓库的桌面方案见 `README.md`）。

> 本文的布局与参数取自本仓库验证过的实践：btrfs 子卷 + zstd 压缩、按 LABEL
> 寻址（跨重装稳定）、swapfile 与内存等大（休眠要求 swap ≥ RAM）、
> `resume_offset` 实测注入。整套流程可在 Live ISO 的 SSH 会话里完成。

## 0. 方案概要

```text
/dev/sda
├── sda1  1G   FAT32 (ESP, LABEL=ESP)   → /boot
└── sda2  剩余  Btrfs (LABEL=nixos)
    ├── @root       → /                     compress=zstd:3,noatime
    ├── @nix        → /nix                  compress=zstd:3,noatime
    ├── @persist    → /persist              compress=zstd:3,noatime
    ├── @swap       → /swap                 noatime（不压缩）
    └── @snapshots  → /persist/.snapshots   noatime（不压缩）
```

四个决定值得先理解，后面步骤都围绕它们：

| 决定 | 理由 |
|------|------|
| 按 LABEL 寻址（`ESP` / `nixos`） | 分区 UUID 每次重装都会变，LABEL 不变，配置可以长期复用 |
| 子卷而非分区 | 快照、单独挂载选项、将来启用 impermanence 都不需要重新分区 |
| `@swap` 不压缩 | btrfs 上压缩的 swapfile 无法 `swapon`（会报 copy-on-write 错误） |
| swapfile 与内存等大 | 休眠要求 swap ≥ RAM；低于此值休眠静默失效 |

内存 < 8G 的机器可以把 swapfile 放宽到 8G（安装期虚拟内存留余量），
装好后按需回收。

## 1. 准备 Live 环境

1. 下载 NixOS ISO（[nixos.org/download](https://nixos.org/download)），写入 U 盘；
   VM 直接挂载 ISO 启动。
2. 启动后确认磁盘（**整盘将被擦除**）：

   ```bash
   lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL
   ```

3. 联网（有线通常自动 DHCP；WiFi 用 `nmtui`），并确认时间正确（TLS 依赖）：

   ```bash
   ping -c1 cache.nixos.org
   timedatectl
   ```

4. 可选但推荐：设置 root 密码并开放 SSH，从宿主机操作更顺手：

   ```bash
   sudo passwd
   sudo systemctl start sshd
   ip -brief addr            # 记下 IP，从另一台机器 ssh root@<ip>
   ```

后续命令均以 root 身份执行（Live ISO 里 `sudo -i`）。

## 2. 分区

```bash
DISK=/dev/sda               # ← 改成你的目标磁盘

parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart ESP  fat32 1MiB 1025MiB
parted "$DISK" -- set 1 esp on
parted "$DISK" -- mkpart root btrfs 1025MiB 100%
partprobe "$DISK"
lsblk "$DISK"               # 确认 sda1 ~1G / sda2 剩余
```

## 3. 格式化与子卷

```bash
mkfs.fat -F 32 -n ESP  "${DISK}1"      # LABEL=ESP
mkfs.btrfs -f -L nixos "${DISK}2"      # LABEL=nixos

mount "${DISK}2" /mnt
for sv in @root @nix @persist @swap @snapshots; do
  btrfs subvolume create "/mnt/$sv"
done
btrfs subvolume list /mnt              # 应列出 5 个子卷
umount /mnt
```

## 4. 挂载

```bash
D="${DISK}2"
OPTS="compress=zstd:3,noatime"

mount -o "subvol=@root,$OPTS" "$D" /mnt
mkdir -p /mnt/{boot,nix,persist,swap}

mount -o "subvol=@nix,$OPTS"     "$D" /mnt/nix
mount -o "subvol=@persist,$OPTS" "$D" /mnt/persist
mount -o "subvol=@swap,noatime"  "$D" /mnt/swap

# .snapshots 的挂载点必须建在 @persist 之内 —— 先挂 @persist 再创建目录,
# 否则目录落在 @root 上, 挂载 @snapshots 时会报挂载点不存在
mkdir -p /mnt/persist/.snapshots
mount -o "subvol=@snapshots,noatime" "$D" /mnt/persist/.snapshots

mount "${DISK}1" /mnt/boot
findmnt -R /mnt            # 确认 6 条挂载
```

## 5. swapfile 与 resume_offset

swapfile 大小取内存上取整（GiB）：

```bash
RAM_G=$(( ($(awk '/MemTotal/{print $2}' /proc/meminfo) + 1048575) / 1048576 ))
echo "swapfile 大小: ${RAM_G}G"

btrfs filesystem mkswapfile --size "${RAM_G}G" /mnt/swap/swapfile
chmod 600 /mnt/swap/swapfile
swapon /mnt/swap/swapfile          # 安装期就可用（也加速构建）

# 关键：休眠恢复偏移（内核从 cmdline 读，单位是页）
btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile
```

**把最后一条命令的输出记下来**（例如 `34743552`），第 7 步要写进
`boot.kernelParams`。这个值在 btrfs balance 移动 swapfile 后会变，
届时重查一次即可。

> `btrfs filesystem mkswapfile` 会自动做 NOCOW + mkswap；不要手工
> `fallocate`/`truncate` 造 swapfile（无 NOCOW 时 `swapon` 报
> `swapfile must not be copy-on-write`）。

## 6. 生成硬件配置

```bash
nixos-generate-config --root /mnt
```

生成 `/mnt/etc/nixos/hardware-configuration.nix`：内核模块、`fileSystems`
（从当前挂载推导，含 `subvol=` 与压缩选项）都在里面，**不要手抄**——
它是本机实测结果。检查一眼 `fileSystems` 与 `swapDevices` 是否齐全：

```bash
grep -A5 'fileSystems\|swapDevices' /mnt/etc/nixos/hardware-configuration.nix
```

若第 5 步已 `swapon`，`swapDevices` 会被自动写入；否则手工补：

```nix
swapDevices = [ { device = "/swap/swapfile"; } ];
```

## 7. 写系统配置

用 flake 组织（便于版本管理与后续多机复用）。目录就用
`/mnt/etc/nixos`：

```bash
cd /mnt/etc/nixos
cat > flake.nix <<'EOF'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs = { self, nixpkgs }: {
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
EOF
```

`configuration.nix` —— 一份可直接用的无桌面最小配置：

```nix
{ config, lib, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  ### 引导（单系统）
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # 双系统 / 需要 os-prober 探测 Windows 时改用 GRUB，见附录 A

  ### 文件系统与休眠
  boot.supportedFilesystems = [ "btrfs" ];
  boot.resumeDevice = "/dev/disk/by-label/nixos";
  boot.kernelParams = [
    "resume_offset=在此填入第 5 步的偏移值"
  ];

  ### 网络
  networking.hostName = "server";
  networking.networkmanager.enable = true;   # nmcli/nmtui 管理，WiFi 也走它
  # 纯有线最小系统可不开 NM：默认 DHCP 即可（删掉上面一行）

  ### SSH（无桌面环境的主要入口）
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;   # 只允许密钥登录
      PermitRootLogin = "no";
    };
  };
  # services.openssh 开启时防火墙会自动放行 22 端口，无需手写规则

  ### 时区 / 语言
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

  ### 用户（把公钥换成你自己的）
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... your-key"
    ];
  };

  ### Nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  ### 基础工具
  environment.systemPackages = with pkgs; [
    vim git curl wget htop btop tmux rsync
  ];

  ### 自动升级（可选；生产环境建议先手动验证再开）
  system.autoUpgrade.enable = false;

  system.stateVersion = "26.05";   # 首次安装时的版本，之后不要改
}
```

## 8. 安装

```bash
nixos-install --flake /mnt/etc/nixos#server --no-channel-copy --no-root-password
```

`--no-root-password` 表示 root 不设密码（仅密钥登录用户账户）；
`--no-channel-copy` 在 flake 场景下不需要复制 channel。若确实需要 root
密码，去掉 `--no-root-password`，安装过程会提示设置。

装完后重启：

```bash
umount -R /mnt
reboot
```

拔掉 U 盘 / 卸载 ISO。

## 9. 首次启动验证

```bash
findmnt -R /                 # 5 个 btrfs 子卷挂载齐全
swapon --show                # /swap/swapfile 已激活
cat /proc/cmdline            # 含 resume_offset=<你的值>
systemctl --failed           # 应为空
```

休眠验证（可选，确认 swap/resume 配置正确）：

```bash
sudo systemctl hibernate     # 唤醒后应恢复原会话
```

> 若 `systemctl hibernate` 被 logind 拒绝（systemd 260 + 新内核下 btrfs
> swap 的 `CanHibernate` 判定可能返回 `na`），可改用直写内核的
> `hibernate-now` 方案 —— 实现见本仓库 `modules/nixos/boot.nix`。

## 10. 日常维护

```bash
# 升级（flake）
sudo nixos-rebuild switch --flake /etc/nixos#server

# 或先验证再切换
sudo nixos-rebuild build --flake /etc/nixos#server

# 更新依赖
nix flake update                  # 在 /etc/nixos 下

# 回滚（NixOS 的安全网：每次 switch 都是一个新 generation）
sudo nixos-rebuild switch --rollback
```

快照（`@snapshots` 已就位，装 snapper 后即可用）：

```bash
# configuration.nix 里加：
#   environment.systemPackages = [ pkgs.snapper ];
#   services.snapper.configs.persist = {
#     SUBVOLUME = "/persist";
#     TIMELINE_CREATE = true;
#   };
sudo snapper -c persist list
```

## 附录 A：用 GRUB 代替 systemd-boot

双系统（需要 `os-prober` 探测 Windows）或固件对 systemd-boot 支持不佳时：

```nix
boot.loader = {
  efi.canTouchEfiVariables = true;
  grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";        # UEFI 下固定为 "nodev"
    useOSProber = true;      # 探测其他系统
  };
};
```

## 附录 B：常见问题

**`swapon` 报 `swapfile must not be copy-on-write`**
用了 `fallocate`/`truncate` 造文件。删掉重建：`btrfs filesystem mkswapfile --size <N>G /swap/swapfile`。

**休眠唤醒后回到旧会话或直接冷启动**
`resume_offset` 过期（btrfs balance 移动过 swapfile）。重查：

```bash
btrfs inspect-internal map-swapfile -r /swap/swapfile
```

更新 `boot.kernelParams` 后 `nixos-rebuild switch`。

**磁盘满了但 `du` 看不到大文件**
快照占用（`@snapshots` 子卷）。`btrfs filesystem usage /` 查看，`snapper list` 清理。

**忘了 swapfile 大小是否达标**
`swapon --show` 的 SIZE 应 ≥ `free -h` 的内存值；不足时重建 swapfile 并重查 `resume_offset`。
