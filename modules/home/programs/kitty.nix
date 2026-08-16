# 终端模拟器 kitty(Catppuccin Mocha 配色)
{ ... }:
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
      include themes/noctalia.conf
    '';
  };
}
