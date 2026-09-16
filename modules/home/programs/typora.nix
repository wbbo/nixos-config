# Typora (Flatpak) 用户级定制 —— 声明式
#
# 两个关注点, 都作用于**用户文件**(而非 Typora 内建资源), 因而不受版本升级覆盖:
#
#  1. autoHideMenuBar  —— 让 Electron 原生菜单栏不常驻 (按 Alt 仍会浮出, 见下)
#  2. base.user.css    —— 恢复 HTML 顶栏, 让汉堡菜单按钮 (☰) 可见
#
# 二者是**协同**关系, 不是各自独立:
#   原生菜单栏常驻时会占住窗口顶部, 把 top:0 的 HTML 顶栏挤到它下方 (两条叠着);
#   autoHideMenuBar 让原生栏退场, HTML 顶栏才能落回原位 —— 即 Windows「一体化」
#   的观感 (☰ + 标题, 无独立菜单栏行)。故 (1) 必须保持开启, 关掉会退化成两条。
#
# 为什么用激活钩子而不是 home.file —— 两条硬约束:
#   1. conf.user.json 由 Typora **自己维护**: 实测启动后 3 秒即被写回一次。交给
#      HM 做符号链接会重演 2026-09-14 的 clobber 事故 (HM 拒绝覆盖实体文件, 激活
#      exit 4); 反过来若让它成为符号链接, Typora 也写不进去。
#   2. conf.user.json 是 **JSONC**(带 // 注释), jq 无法解析, 只能定点文本替换。
#
# 原则: conf.user.json **只改 autoHideMenuBar 一个字段**, 其余键与注释原样保留 ——
# 用户在 Typora GUI 里改的其他设置 (字体/快捷键/搜索服务等) 不会被动。
# base.user.css 则是整文件由本模块拥有 (Typora 不写它), 内容比对幂等。
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

  typoraConfDir = "${homeDir}/.var/app/io.typora.Typora/config/Typora";
  confFile = "${typoraConfDir}/conf/conf.user.json";
  themesDir = "${typoraConfDir}/themes";
  baseUserCss = "${themesDir}/base.user.css";

  # ---------------------------------------------------------------------------
  # base.user.css —— 恢复 HTML 顶栏 (#top-titlebar), 让汉堡按钮 (☰) 可见
  #
  # 背景: Windows「一体化」在无边框窗口左上角有个 ☰ 按钮 (点开=菜单)。
  # Linux 构建里**这个按钮存在**, 只是连整条顶栏一起被隐藏了:
  #
  #   window.html:  <div id="top-titlebar">
  #                   <span id="w-menu-btn">          ← ☰ 本体
  #                     <span class="ty-menu-btn-area-sub ty-menu-btn-area-sub1"></span>
  #                     ...sub2 ...sub3               ← 三条横线
  #   window.css:   .native-window #top-titlebar { display:none }   ← 唯一让它消失的规则
  #
  # 而 native-window 是**硬编码在 window.html 的 body 上**的:
  #   <body class="typora-node native-window no-collapse-outline allow-file-tree-scroll">
  # 主进程字节码只**读**它 (classList.contains("native-window")), 从不写它;
  # Windows 一体化用的是另一套 class unibody-window —— CSS 里有 10 处规则而字节码
  # 里 0 处, Linux 构建从不添加。故此处用 CSS 覆盖 display 即可, 无需改程序。
  #
  # 为什么能安全恢复:
  #   #top-titlebar { top:0; position:absolute; right:0; height:24px }
  #   content       { top:28px }        ← 这 28px 空白本来就是给它留的
  # 二者吻合, 恢复后正好填回原位 —— 用户实测截图里"菜单栏隐藏后留下的一条空白"
  # 即是这个空位。配色也随之正确: #top-titlebar 是 background-color:inherit, 从
  # html 继承到 var(--bg-color); 实测顶栏与正文区同色。
  #
  # **已知残留 (实测, 非推断)**: 按 Alt 仍会浮出 **Electron 原生菜单栏**, 且它的
  # 背景仍是 #222329 (与主题的 #363b42 不一致)。这条无解 ——
  #   - Chromium 原生绘制, CSS 够不着 (它不是 DOM 元素);
  #   - 曾试 "framelessWindow": true (Windows 一体化的机制, 字节码中确有该键),
  #     实测在 Linux 上**不生效**, 按 Alt 依旧浮出 —— 与"设置界面只在 Windows
  #     渲染它"一致, 该功能整条链路只在 Windows 实现。
  # 故自动隐藏后, 这条异色菜单栏仅在主动按 Alt 时短暂可见, 影响有限, 不再处理。
  # 另注: 恢复顶栏后, 按 Alt 会同时出现两条 (原生菜单栏占窗口顶部, 把 top:0 的
  # HTML 顶栏挤到其下方) —— 这是 autoHideMenuBar 定义内的行为, 非本规则的缺陷;
  # 若把 autoHideMenuBar 关掉, 原生菜单栏会常驻, 观感更差。
  #
  # 落到 base.user.css (而非 night.user.css): 规则是平台相关而非主题相关。
  # 官方机制见 themes/Readme.md —— 内建主题会在版本升级时被 overwriteThemeFolder
  # 整个覆盖 ("DO NOT MODIFY THEM"), 自定义须写 *.user.css; frame.js 实证
  # #base_user_css / #theme_user_css 两个 <link> 在主题之后加载, 故天然覆盖。
  # ---------------------------------------------------------------------------
  baseUserCssSource = pkgs.writeText "typora-base.user.css" ''
    /* 由 NixOS 仓库 modules/home/programs/typora.nix 声明式管理 —— 手工修改会在
     * 下次 ./build.sh 时被覆盖。改这里: modules/home/programs/typora.nix */

    /* 恢复 HTML 顶栏, 使汉堡菜单按钮 (☰) 可见。
     * 内建 window.css 的 .native-window #top-titlebar{display:none} 把整条顶栏
     * (含 #w-menu-btn) 隐藏了; body 上的 native-window class 是硬编码的, Linux
     * 构建不会切到 Windows 的 unibody-window, 故直接覆盖 display。
     * 选择器与权重同原规则, base.user.css 后加载故胜出。 */
    .native-window #top-titlebar {
        display: block;
    }
  '';
in
{
  # ---------------------------------------------------------------------------
  # 1. 菜单栏不常驻 (autoHideMenuBar)
  #
  # 官方进阶设置, 原文见 conf.default.json:
  #   "autoHideMenuBar": true   // Auto hide the menu bar unless the `Alt` key is pressed
  #
  # 为什么需要它: Typora 的 Linux 构建没有 Windows「一体化」(Unibody) —— 该设置项
  # keyName 为 framelessWindow, 门控是 forWin + visible:isMacNode (Preferences.*.js),
  # 运行时在 Linux 上两项皆不成立, 条目根本不渲染 (不是灰掉)。autoHideMenuBar 是
  # 官方给出的等价手段。
  #
  # 生效时机 (2026-09-16 二分实验实证, 非推断): 该设置**确实有效** —— 对照组
  # false 菜单栏显示, 实验组 true 菜单栏隐藏且 Alt 可切换。但注意两点:
  #   - "先有文件再定点改", 故新机器一次 build 即生效 —— 文件不存在时直接创建最小
  #     文件 (Typora 启动时会与 conf.default.json 合并, 效果一致), 不需要"先跑一次
  #     Typora 再 build"的额外往返。
  #   - **改完必须完全退出所有 Typora 实例再启动**。Typora 是单实例应用: 已有实例
  #     存活时再"打开"只是把窗口拉到前台, 主进程不重读配置、不重建菜单 —— 表现为
  #     "改了没反应"。本轮排查中 14:29 那次启动即因此误判过一次 (同一个 true, 14:29
  #     不生效、16:01 生效, 差异只在是否从零启动)。
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # 2. base.user.css (恢复 HTML 顶栏 / 汉堡按钮)
  # ---------------------------------------------------------------------------
  home.activation.typora-base-user-css = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # themes/ 由 Typora 首次启动时创建 —— 目录不在说明尚未运行过, 本轮跳过
    # (下次 build 补上), 不主动建目录 (建了也会被 overwriteThemeFolder 重排)。
    if [ -d "${flatpakInstalled}" ] || [ -d "${flatpakInstalledUser}" ]; then
      if [ -d "${themesDir}" ]; then
        if [ -f "${baseUserCss}" ] \
          && ${pkgs.diffutils}/bin/cmp -s "${baseUserCssSource}" "${baseUserCss}"; then
          : # 内容一致, 幂等跳过
        else
          ${pkgs.coreutils}/bin/install -Dm644 "${baseUserCssSource}" "${baseUserCss}"
          echo "==> typora: base.user.css 已写入 (恢复 HTML 顶栏 / 汉堡按钮)"
        fi
      fi
    fi
  '';
}
