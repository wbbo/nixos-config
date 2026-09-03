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

  # 中途迁移适配: 目标已存在普通文件时 impermanence 激活按数据保护拒绝
  # (bind mount 目标不能有旧数据), 需把 ~ 下的真实数据先移入 /persist 端。
  # 本钩子在目录创建 (persist-files) 之后、bind unit 启动之前执行:
  # 目标不存在 (全新安装) 或已是挂载点 (正常状态) 时跳过, 一次生效后幂等。
  # 仅精确路径条目; 通配条目跳过 (无法安全展开迁移)。
  home.activation.persistMigrate = lib.hm.dag.entryAfter [ "persist-files" ] ''
    for entry in ${lib.escapeShellArgs persistFiles}; do
      case "$entry" in
        *"*"*) continue ;;
      esac
      target="$HOME/$entry"
      if { [ -e "$target" ] || [ -L "$target" ]; } && ! mountpoint -q "$target"; then
        source="/persist/home/${mainUser}/$entry"
        mkdir -p "$(dirname "$source")"
        mv -n -- "$target" "$source"   # -n: /persist 端已有数据时不覆盖
      fi
    done
  '';
}
