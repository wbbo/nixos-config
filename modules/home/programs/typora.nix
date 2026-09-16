# Typora (Flatpak) 进阶配置 —— 声明式, 但**只动一个字段**
#
# 背景: Typora 的 Linux 构建没有 Windows「一体化」(Unibody) 那种「菜单栏不占一行」
# 的形态 —— 窗口样式 (Classic/Unibody) 是 forWin 门控, 运行时在 Linux 上永不成立。
# 但官方另有一个等价的进阶设置:
#
#   "autoHideMenuBar": true   // Auto hide the menu bar unless the `Alt` key is pressed
#
# 菜单栏不再常驻占一行, 按 Alt 临时浮出。本模块把它声明化。
#
# 为什么用激活钩子而不是 home.file —— 两个硬约束:
#   1. 该文件由 Typora **自己维护**: 实测启动后 3 秒即写回一次。交给 HM 做符号
#      链接会重演 2026-09-14 的 clobber 事故 (HM 拒绝覆盖实体文件, 激活 exit 4);
#      反过来若让它成为符号链接, Typora 也写不进去。
#   2. 文件是 **JSONC**(带 // 注释), jq 无法解析, 只能定点文本替换。
#
# 原则: **只改 autoHideMenuBar 这一个字段**, 其余键与注释一律原样保留 ——
# 用户后续在 Typora GUI 里改的其他设置 (字体/快捷键/搜索服务等) 不会被动。
#
# 生效时机: 因为是"先有文件再定点改", 首次在新机器上生效只需**一次 build** ——
# 文件不存在时直接创建最小文件 (Typora 启动时会与 conf.default.json 合并,
# 效果与完整文件一致), 不需要"先跑一次 Typora 再 build"的额外往返。
{ config, lib, pkgs, ... }:
let
  homeDir = config.home.homeDirectory;

  # Flatpak 安装判据 —— **不能**用 ~/.var/app/io.typora.Typora 判断:
  # 该路径在 persist.nix 的持久化清单里, impermanence 以 bind mount 建立它
  # (findmnt 实测: /dev/sda2[/@persist/home/<user>/.var/app/io.typora.Typora]),
  # 于是不论 Typora 装没装, 这个目录**永远存在** —— 拿它当判据恒为真,
  # 等于没有守卫。改用 Flatpak 自身的安装目录 (系统级 / 用户级两种装法)。
  flatpakInstalled = "/var/lib/flatpak/app/io.typora.Typora";
  flatpakInstalledUser = "${homeDir}/.local/share/flatpak/app/io.typora.Typora";

  confFile = "${homeDir}/.var/app/io.typora.Typora/config/Typora/conf/conf.user.json";
in
{
  home.activation.typora-auto-hide-menu-bar = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # 注意: 激活脚本是平铺的 set -eu, 任何分支都**不能 exit** ——
    # 会静默截断后续钩子 (同 fcitx5.nix 的教训)。条件分支用 if/elif 收敛即可。
    if [ -d "${flatpakInstalled}" ] || [ -d "${flatpakInstalledUser}" ]; then
      if [ ! -f "${confFile}" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "${confFile}")"
        ${pkgs.coreutils}/bin/printf '{\n  "autoHideMenuBar": true\n}\n' > "${confFile}"
        echo "==> typora: 已创建 conf.user.json (autoHideMenuBar=true)"
      elif ${pkgs.gnugrep}/bin/grep -q '"autoHideMenuBar"[[:space:]]*:[[:space:]]*true' "${confFile}"; then
        : # 已是目标值, 幂等跳过 (绝大多数构建走这条)
      elif ${pkgs.gnugrep}/bin/grep -q '"autoHideMenuBar"[[:space:]]*:[[:space:]]*false' "${confFile}"; then
        ${pkgs.gnused}/bin/sed -i -E \
          's/("autoHideMenuBar"[[:space:]]*:[[:space:]]*)false/\1true/' "${confFile}"
        echo "==> typora: autoHideMenuBar false -> true"
      else
        echo "警告: typora conf.user.json 中未找到 autoHideMenuBar 字段, 未做改动" >&2
      fi
    fi
    # 未安装 Flatpak 版 Typora 时静默跳过 —— 既不改文件, 也不建目录
  '';
}
