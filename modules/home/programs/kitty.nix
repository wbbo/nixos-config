# 终端模拟器 kitty(Catppuccin Mocha 配色)
{ pkgs, ... }:
{
  programs.kitty = {
    enable = true;
    settings = {
      # Maple Mono: 等宽 + Nerd 图标 + CJK (反白表头发虚为渲染层面, 用 htop 规避)
      font_family = "Maple Mono NF CN";
      bold_font = "auto";
      italic_font = "auto";
      bold_italic_font = "auto";
      font_size = "12.0";

      window_padding_width = "8 12";
      cursor_shape = "beam";
      cursor_blink_interval = "0.5";
      scrollback_lines = 10000;
      copy_on_select = "clipboard";
      strip_trailing_spaces = "smart";
      enable_audio_bell = "no";

      ### Catppuccin Mocha
      foreground = "#cdd6f4";
      background = "#1e1e2e";
      selection_foreground = "#1e1e2e";
      selection_background = "#f5e0dc";
      cursor = "#f5e0dc";
      cursor_text_color = "#1e1e2e";
      url_color = "#89b4fa";

      # normal
      color0 = "#45475a";  color1 = "#f38ba8";  color2 = "#a6e3a1";
      color3 = "#f9e2af";  color4 = "#89b4fa";  color5 = "#f5c2e7";
      color6 = "#94e2d5";  color7 = "#bac2de";
      # bright
      color8 = "#585b70";  color9 = "#f38ba8";  color10 = "#a6e3a1";
      color11 = "#f9e2af"; color12 = "#89b4fa"; color13 = "#f5c2e7";
      color14 = "#94e2d5"; color15 = "#a6adc8";
    };

    # X11 终端习惯的粘贴键: Shift+Insert 由 kitty 层处理 (覆盖所有终端内程序)。
    # Ctrl+Insert 不再绑定 (放行给终端内应用, 如 neovim 的复制选中到系统剪贴板)。
    keybindings = {
      "shift+insert" = "paste_from_clipboard";
    };

    # 动态取色: 引入 Noctalia 渲染的 noctalia.conf (壁纸 M3 取色, 见 noctalia.nix
    # [theme.templates] builtin_ids=["kitty"])。放在文件末尾覆盖 Catppuccin 基础色,
    # 壁纸变化时 Noctalia 重新渲染 + 内置 apply.sh 发 SIGUSR1 重载 kitty。
    # 注意: include 已声明在配置中, apply.sh 检测到存在即跳过 mv (不破坏 home-manager symlink)。
    extraConfig = ''
      # 【2026-10-15】符号回退 + kitty 格数规则 (源码级实测):
      # Maple Mono NF CN 缺 ①②③(U+2460-24FF) 与 ★☆(U+2605-2606) 字形, 显式
      # 映射到 Noto Sans Mono CJK SC —— 全角设计 (圈/星墨迹 93% em, 与汉字同级)。
      # 但屏幕上多大还会被 **kitty 的格数分配**二次限制 (fonts.c:2235 分支,
      # 仅对"非主字体 + category=So 符号"或 PUA 生效):
      #   - ①②③ category=No, 恒占 1 格 → 缩放至 ~63% em, 相对汉字(2 格)显小。
      #     无解: kitty 只有 narrow_symbols 可收窄, 没有加宽选项; 换任何字体
      #     都一样 (DejaVu/Unifont 的星/圈更小, 16px 下墨迹近零)。
      #   - ★☆ category=So: **后跟空格**时吸收空格按 2 格原尺寸渲染 (饱满);
      #     后跟非空格时只能 1 格 → 缩放 ~63%。故 "★☆" 相邻时 ★ 显小、
      #     "★ ☆" 则等大 —— 是特性而非缺陷。想求恒一可用
      #     `narrow_symbols U+2605-U+2606` 强制 1 格 (已评估, 选择保持现状)。
      symbol_map U+2460-U+24FF Noto Sans Mono CJK SC
      symbol_map U+2605-U+2606 Noto Sans Mono CJK SC

      include themes/noctalia.conf
    '';
  };

  # xdg-terminal-exec: freedesktop 的终端选择规范工具, 按
  # ~/.config/xdg-terminals.list 的优先级挑终端 (每行一个 desktop 文件名,
  # 取第一个可用的), 此处指定 kitty。供遵循该规范的程序使用。
  # 注: Nautilus 的"在终端中执行"右键项**不走**这条路径 —— 它由 python 扩展
  # nautilus-open-any-terminal 提供 (见 programs/nautilus.nix), 实测该扩展
  # 与 xdg-terminal-exec 无关; 早前此处"需 xdg-terminal-exec 才出现菜单项"
  # 的注释是误判, 已更正。
  home.packages = [ pkgs.xdg-terminal-exec ];

  xdg.configFile."xdg-terminals.list".text = ''
    kitty.desktop
  '';
}
