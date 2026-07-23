# 终端模拟器 kitty(Catppuccin Mocha 配色)
{ ... }:
{
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrainsMono Nerd Font";
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
  };
}
