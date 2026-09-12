# 家目录持久化(用户级)—— impermanence 声明
# @root 会被快照回滚/重建, @persist 由 snapper 保护 (跨重建保留)。
# home.persistence 的 attr 名是持久化根路径 (不含家目录, 自动拼接),
# 数据实际落在 /persist/home/<user>/<dir>, 与本仓库既有布局一致。
# 实现为 boot 期 root bind mount (~/<dir> <-> /persist/home/<user>/<dir>),
# 对应用不可见 (真实目录), 早于登录生效。
# 只用目录级 bind, 不用文件级 bind: 文件 bind 有运行时再生竞态
# (fcitx5 运行时再生 yaml 挡住 bind 曾致 activation 失败 exit 4,
# 当年为此引入的 persistMigrate 迁移钩子已随整目录化退役)。
{ ... }:
{
  home.persistence."/persist" = {
    directories = [
      # 编译链缓存/配置 (大、下载慢, 重装后保留): maven/gradle/rust/go/node/pnpm/npm/uv
      ".claude"
      ".m2"
      ".gradle"
      ".rustup"
      ".cargo"
      ".nvm"
      ".local/state"           # 应用运行时状态 (niri 分辨率、noctalia settings 等)
      ".local/share/nvm"
      "go"
      ".local/share/pnpm"
      ".npm"
      ".cache/uv"
      "code"                   # 源代码仓库 (含本配置, snapper 保护)
      "apps"                   # 应用/工具目录 (ventory 等, snapper 保护)
      # Pictures: 图片收藏 + 壁纸库 + niri 内置截图输出。
      # Noctalia 轮播池与视频壁纸在 Pictures/Wallpapers 下, 见 noctalia.nix;
      # niri 的 screenshot-path 指向 Pictures/screenshot (config.kdl) ——
      # 原顶层 ~/screenshot 已并入此处, 其独立 bind 条目随之移除 (挂载点
      # 无法 mv, 迁移靠改配置 + rebuild 完成)。
      "Pictures"
      # 脚本安装工具 (claude/codex/cc-switch): 二进制 + 版本目录 + codex 登录态。
      # 重装(@root 重建)后保留, 补装用户服务"缺失才下载"不再触发, 消除下载依赖;
      # .claude 配置目录在上面已持久化。
      ".local/bin"
      ".local/share/claude"
      ".codex"
      # cc-switch 数据目录 (配置切换器, 拒绝 symlink 故必须 bind — impermanence
      # 目录持久化即 bind, 满足)。原为 modules/nixos/persist.nix 手写挂载, 已并入。
      ".cc-switch"
      # fcitx5/rime 输入法数据整目录持久化: userdb=词频/自造词, sync=词库
      # 快照, user.yaml/installation.yaml=方案选择与同步设备身份
      # (installation_id 变了会被 sync 当新设备)。整目录 bind 取代原先
      # 2 目录 + 2 文件共 4 条 bind, 消灭文件级 bind 竞态 (见文件头注释)。
      # build/ 编译产物 (~73M) 一并持久: 可重建, 体量可接受, 换清单极简。
      ".local/share/fcitx5/rime"
      # pigma (TUI 网易云) 配置与登录态
      ".config/pigma"
      # Thunderbird: 账户配置/服务器设置/地址簿/本地邮件都在 profile 内,
      # 不持久化则重装(@root 重建)后需重配全部邮箱账户。
      # 注意: IMAP 账户的离线邮件缓存也在其中, 会随使用增长。
      ".thunderbird"
      # Flatpak 应用数据 (系统级装 /var/lib/flatpak 跨 rebuild 天然保留, 但
      # ~/.var/app/<app> 在 @root 属家目录需显式持久化):
      # - com.usebottles.bottles: Bottles wineprefix + 下载的 runner/组件
      #   (wineprefix 内含已装 Windows 应用, 无法重建, 必须持久化)
      # - com.tencent.WeChat: 微信聊天记录/登录态 (~300M)
      ".var/app/com.usebottles.bottles"
      ".var/app/com.tencent.WeChat"
      # Lutris 游戏启动器: ~/.local/share/lutris 含自行下载的 wine runner /
      # DXVK 与每个游戏的配置 (重下费时), ~/.config/lutris 为启动器设置。
      # 注意: 游戏本体默认装在 ~/Games, 不在持久化范围 (体积大, 按需自定)。
      ".local/share/lutris"
      ".config/lutris"
      # Steam 游戏平台: 整个 ~/.local/share/Steam 一个目录装齐了游戏本体
      # (steamapps/common)、Proton prefix (compatdata, Windows 存档在内)、
      # 云同步缓存与客户端设置。不持久化则每次重启全部丢失 —— 实测下载到
      # 6.6G 后重启即清零。
      # 注: 放进 @persist 会进 snapper 快照, 但 btrfs 快照是 COW, 游戏文件
      # 下载后基本不变, 快照几乎不额外占空间; 唯一代价是删游戏后空间延迟
      # 释放 (等快照过期, 本机策略最长 6 个月)。
      # 迁移记录: 首次接管时 ~/.local/share/Steam 是临时根上的真实目录,
      # 需先 cp -a 到 /persist/home/wbb/.local/share/ 再清空原目录留作挂载点,
      # 否则 bind mount 会把已有数据整个遮住。
      ".local/share/Steam"
    ];
  };
}
