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
}
