# Nautilus 文件管理器增强
{ pkgs, ... }:
{
  # "在终端中打开"**顶层**右键菜单项 —— 用社区扩展 nautilus-open-any-terminal
  # (python 扩展, 由 nautilus-python 加载)。
  #
  # 三方协作 (缺一不可):
  # 1. modules/nixos/packages.nix: nautilus 被 override, 把 libnautilus-python.so
  #    软链进它自己的 lib/nautilus/extensions-4/ —— Nautilus 只扫该目录,
  #    不搜索 XDG (二进制内硬编码单一路径, 实测), 不注入则加载器不可见。
  # 2. 本文件: 扩展 .py 投放到 XDG 的 nautilus-python/extensions/ (加载器
  #    从这里扫描), 走 xdg.dataFile 而非 home.packages —— HM buildEnv 的
  #    pathsToLink 不含 share/nautilus-python, 装了到不了位。
  # 3. dconf: 告诉扩展用哪个终端 (读 gsettings com.github.stunkymonkey.
  #    nautilus-open-any-terminal 的 terminal 键)。
  #
  # 注: kitty.nix 里的 xdg-terminal-exec 是另一套规范, Nautilus 不使用。
  xdg.dataFile."nautilus-python/extensions/nautilus_open_any_terminal.py".source =
    "${pkgs.nautilus-open-any-terminal}/share/nautilus-python/extensions/nautilus_open_any_terminal.py";

  # 本地化 —— 扩展源码把翻译搜索路径硬编码为
  # [~/.local/share/locale, /usr/share/locale] (第 47 行), NixOS 上既没有
  # /usr/share/locale、包内 store 路径也不在搜索范围, 故菜单回退英文。
  # 把包内自带的中文 .mo 投放到用户级 localedir 解决。
  xdg.dataFile."locale/zh_CN/LC_MESSAGES/nautilus-open-any-terminal.mo".source =
    "${pkgs.nautilus-open-any-terminal}/share/locale/zh_CN/LC_MESSAGES/nautilus-open-any-terminal.mo";
  xdg.dataFile."locale/zh_TW/LC_MESSAGES/nautilus-open-any-terminal.mo".source =
    "${pkgs.nautilus-open-any-terminal}/share/locale/zh_TW/LC_MESSAGES/nautilus-open-any-terminal.mo";

  dconf.settings."com/github/stunkymonkey/nautilus-open-any-terminal" = {
    terminal = "kitty";
  };

  # 侧边栏补回「文件系统」(root /) 入口。
  # Nautilus 的侧边栏是 GTK 的 GtkPlacesSidebar, 它按 glib 的
  # g_unix_mount_guess_should_display() 决定显示哪些挂载 —— 挂载点为 "/"
  # 的一律判为 system internal 不予显示 (实测 `gio mount -l` 也只列出外接
  # 卷, 没有 /)。GNOME 的设计假设是"根目录不是日常去处", 要经
  # "其他位置 → 计算机"(computer:///) 才到。对比之下 Thunar 侧边栏有
  # 「文件系统」, 是因为它用自家 shortcuts 模型硬编码了该条目。
  # 这里用书签补回, 由 HM 声明式管理。
  # 注意路径是 gtk-3.0: Nautilus 虽已是 GTK4 应用, 书签文件路径仍硬编码为
  # ~/.config/gtk-3.0/bookmarks (见上游 src/nautilus-bookmark-list.c),
  # 写 gtk-4.0 不生效。
  # 代价: 该文件被 HM 接管为只读符号链接, 之后在 GUI 里 Ctrl+D 增删书签
  # 写不进去 (重启即丢) —— 增减书签改为改此处配置后 rebuild。
  xdg.configFile."gtk-3.0/bookmarks" = {
    text = "file:/// 文件系统\n";
    # GTK/Nautilus 首次运行会自建一个空的 bookmarks 文件, 而 HM 默认拒绝覆盖
    # 已存在文件 (激活时报 "Existing file ... would be clobbered" 并整体
    # 失败, 连带 switch 退出码 4), 故强制覆盖。
    force = true;
  };
}
