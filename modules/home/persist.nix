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
    # hideMounts: 让 impermanence 生成的 bind mount 直接带 x-gvfs-hide,
    # GVFS/udisks2 就不会把持久化目录当"挂载卷"上报, 文件管理器侧边栏不再
    # 显示它们。impermanence 的 submodule-options.nix 里每个目录的 hideMount
    # 默认值继承本项, 故声明一次即全局生效 —— 挂载时即隐藏, 不需要任何事后
    # remount 补救 (原 modules/nixos/persist.nix 的 hide-persist-mounts 服务
    # 因此退役, 那方案对新增目录还会漏)。
    # ⚠ 但"挂载时即隐藏"意味着**只对此后新建立的挂载生效**, 已挂载的不受影响:
    # x-gvfs-hide 是纯用户态选项 (x- 前缀不进内核, 故 findmnt / mountinfo 里
    # 根本看不到它), GVFS 判断卷是否上报读的是 /run/mount/utab —— 而该文件在
    # mount(8) 建立挂载的那一刻写入。bind 是**开机时**建立的, systemd 又不会
    # 因为 .mount 单元的 Options 变了就重挂已激活的挂载, 所以 **rebuild 不生效,
    # 必须重启**。症状: 启用后文件管理器里仍能看到 apps / code / go —— 同批一共
    # 22 个陈旧挂载, 其余 19 个是点目录 (默认不显示) 才没暴露出来。
    hideMounts = true;
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
      # 录屏输出 (wf-recorder, Mod+Alt+R 切换)。4K 编码文件体积大, 不持久化
      # 则重启即丢; 与 Pictures 同属"用户产出物", 一并持久化便于统一管理。
      "Videos"
      # 浏览器/应用默认下载位置 (XDG_DOWNLOAD_DIR 已统一指向它, 见
      # modules/home/default.nix 的 xdg.userDirs)。此前不在清单里, 一直落在
      # 临时根上 —— 重启即丢, 下载的东西需要及时挪走。
      "Downloads"
      # 文档目录 —— Obsidian vault 所在 (~/Documents/Obsidian Vault)。笔记
      # 不可重建, 重装/回滚必须保留。迁移要点: 先 cp -a 现有内容到
      # /persist/home/<user>/Documents 再 rebuild (挂载后 @root 侧副本被遮蔽)。
      "Documents"
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
      # Firefox profile —— 数据在 XDG 路径 ~/.config/mozilla (不是 ~/.mozilla,
      # 后者只剩 HM 生成的 native-messaging-hosts 软链, 重装后 HM 自建, 不必持久化):
      # cookie / 登录凭据(cert9.db, logins.json) / 书签与历史(places.sqlite) /
      # 扩展数据全在这里。
      # **曾漏网**: 2026-09-15 重装(@root 重建)后整棵 profile 随之消失, 表现为
      # "cookie 全部失效、所有站点掉登录"; 证据是 profile 内 compatibility.ini /
      # cert9.db 的时间戳 = 重装后首启时刻(22:40), 旧数据无痕。Thunderbird 一直在
      # 清单里, 唯独浏览器被漏掉。
      # 注: 缓存目录 ~/.cache/mozilla 体积大且可重建, 不持久化;
      # search.json.mozlz4 由 HM 管(火狐运行时会把它改写成实体文件, 见 build.sh
      # 预检告警), firefox.nix 的 search.force = true 会在激活时强制覆盖回软链。
      ".config/mozilla"
      # Flatpak 应用数据 (系统级装 /var/lib/flatpak 跨 rebuild 天然保留, 但
      # ~/.var/app/<app> 在 @root 属家目录需显式持久化):
      # - com.usebottles.bottles: Bottles wineprefix + 下载的 runner/组件
      #   (wineprefix 内含已装 Windows 应用, 无法重建, 必须持久化)
      # - com.tencent.WeChat: 微信聊天记录/登录态 (~300M)
      # - io.typora.Typora: Markdown 编辑器 (偏好设置/授权/最近文件)
      # - md.obsidian.Obsidian: 笔记应用 (应用配置/插件/索引; vault 本体
      #   在用户自选路径, 该路径是否持久化需另行确认)
      # - com.obsproject.Studio: 场景集合/配置文件/输出设置
      #   (录屏输出统一落在 ~/Videos/record, 该目录已随 Videos 持久化)
      ".var/app/com.usebottles.bottles"
      ".var/app/com.tencent.WeChat"
      ".var/app/io.typora.Typora"
      ".var/app/md.obsidian.Obsidian"
      ".var/app/com.obsproject.Studio"
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
      # HMCL (Minecraft 启动器) —— 数据**分三处**, 缺一不可 (2026-09-16 实测):
      #   1. ~/.hmcl —— 工作目录相对路径 (nixpkgs wrapper 的 `cd $HOME` 把它定在
      #      家目录; 从别处启动就会跑到别处, 这是相对路径语义)。含 logs / config
      #      (game-directories、launcher-settings、game-settings) / state / cache。
      #   2. ~/.local/share/hmcl —— XDG 数据目录 (由 Java 的 user.home 决定,
      #      不受 $HOME 环境变量影响)。**账户凭据在这里**:
      #      private/user-account-private-data.json + config/user-accounts.json,
      #      另有皮肤缓存 / javaCache.json / user-* 设置。不持久化 = 重装后要重新登录。
      #   3. ~/.minecraft —— 游戏本体默认目录 (同为相对路径, 由那句 cd $HOME 决定):
      #      世界 saves/、模组 mods/、光影 shaderpacks/、游戏配置 config/、
      #      versions/ 与 assets/ 全在这一个目录树下 (开了版本隔离也只是挪到
      #      versions/<版本>/ 内), 重下代价高 (与 Steam/lutris 同理)。
      # 若在 HMCL 内把游戏目录改到别处, 那条路径需另行声明。
      ".hmcl"
      ".local/share/hmcl"
      ".minecraft"
    ];
  };
}
