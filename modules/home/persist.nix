# 家目录持久化(用户级)—— impermanence 声明
# @root 会被快照回滚/重建, @persist 由 snapper 保护 (跨重建保留)。
# home.persistence 的 attr 名是持久化根路径 (不含家目录, 自动拼接),
# 数据实际落在 /persist/home/<user>/<dir>, 与本仓库既有布局一致。
# 实现为 boot 期 root bind mount (~/<dir> <-> /persist/home/<user>/<dir>),
# 对应用不可见 (真实目录), 早于登录生效。
# ~/.cc-switch 例外 (cc-switch 需要 nofail 兜底), 由 nixos/persist.nix 手写
# bind mount + tmpfiles 预建。
# 注意: files 新增条目后, 若 ~ 下已存在真实数据 (首次启用持久化的场景),
# impermanence 激活会按数据保护拒绝 bind — 见下方 activation.persistMigrate
# 钩子, 自动把数据迁进 /persist 端 (幂等, 无需手工搬迁)。
{ mainUser, config, lib, ... }:
let
  persistFiles = [
    ".local/share/fcitx5/rime/user.yaml"
    ".local/share/fcitx5/rime/installation.yaml"
  ];
in
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
      # 脚本安装工具 (claude/codex/cc-switch): 二进制 + 版本目录 + codex 登录态。
      # 重装(@root 重建)后保留, 补装用户服务"缺失才下载"不再触发, 消除下载依赖;
      # .claude 配置目录在上面已持久化。
      ".local/bin"
      ".local/share/claude"
      ".codex"
      # fcitx5/rime 输入法学习数据 (不可再生): userdb=词频/自造词/使用习惯,
      # sync=rime sync 词库快照, user.yaml/installation.yaml=方案选择与
      # 同步设备身份 (installation_id 变了会被 sync 当新设备)。
      # build/ 编译产物 (73M) 不持久化 —— fcitx5RimeRedeploy 钩子可重建;
      # *.custom.yaml 是 HM store 符号链接, 声明式自生成。
      ".local/share/fcitx5/rime/rime_ice.userdb"
      ".local/share/fcitx5/rime/sync"
    ];
    files = persistFiles;
  };

  # 中途迁移 + 竞态自愈 (entryBefore persist-files): 目标已存在普通文件时
  # impermanence 会按数据保护拒绝 bind ("A file already exists"), 且该片段
  # 失败会中止整个 HM 激活 —— 本钩子若排在 persist-files 之后 (entryAfter)
  # 就再没机会执行 (实测踩坑), 故必须先于 persist-files 清障:
  #   目标不存在 (全新安装) 或已是挂载点 (正常状态) → 跳过, 幂等;
  #   /persist 端无数据 → 目标挪入 /persist (首次启用持久化的迁移, -n 防覆盖);
  #   /persist 端已有数据 (fcitx5 运行时在 bind 断窗内再生 yaml 的竞态) →
  #     目标挪成带时间戳的 conflict 备份, /persist 权威数据经 bind 接管。
  #     自 bind 断开以来的运行时状态变化留在备份里 (fcitx5 重部署后从 bind
  #     读权威副本), 备份位于 @root 不持久化, 仅备查可随时删除。
  # 仅精确路径条目; 通配条目跳过 (无法安全展开迁移)。
  # 挂载点判定不可用 mountpoint(1): HM activate 的 PATH 无 util-linux
  # (实测 command not found, rc=127 经 ! 反转恒为真, 已挂载目标也被误判,
  # mv 挂载点报 busy)。改查 /proc/mounts 文本 (路径无空格, 首尾空格界定的
  # 字段匹配足够, bind file 挂载同样登记其中)。
  home.activation.persistMigrate = lib.hm.dag.entryBefore [ "persist-files" ] ''
    is_mounted() { grep -qs " $1 " /proc/mounts; }
    for entry in ${lib.escapeShellArgs persistFiles}; do
      case "$entry" in
        *"*"*) continue ;;
      esac
      target="$HOME/$entry"
      if { [ -e "$target" ] || [ -L "$target" ]; } && ! is_mounted "$target"; then
        source="/persist/home/${mainUser}/$entry"
        mkdir -p "$(dirname "$source")"
        if [ -e "$source" ]; then
          mv -- "$target" "$target.conflict.$(date +%Y%m%d-%H%M%S)" || true
        else
          mv -n -- "$target" "$source"
        fi
      fi
    done
  '';
}
