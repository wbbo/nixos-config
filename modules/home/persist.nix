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
      # 脚本安装工具 (claude/codex/cc-switch): 二进制 + 版本目录 + codex 登录态。
      # 重装(@root 重建)后保留, 补装用户服务"缺失才下载"不再触发, 消除下载依赖;
      # .claude 配置目录在上面已持久化。
      ".local/bin"
      ".local/share/claude"
      ".codex"
      # fcitx5/rime 输入法数据整目录持久化: userdb=词频/自造词, sync=词库
      # 快照, user.yaml/installation.yaml=方案选择与同步设备身份
      # (installation_id 变了会被 sync 当新设备)。整目录 bind 取代原先
      # 2 目录 + 2 文件共 4 条 bind, 消灭文件级 bind 竞态 (见文件头注释)。
      # build/ 编译产物 (~73M) 一并持久: 可重建, 体量可接受, 换清单极简。
      ".local/share/fcitx5/rime"
      # pigma (TUI 网易云) 配置与登录态
      ".config/pigma"
    ];
  };
}
