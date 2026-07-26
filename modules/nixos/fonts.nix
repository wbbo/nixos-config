# 字体:中文 + 英文 + 等宽(Nerd Font)+ Emoji
{ pkgs, ... }:
{
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      # Maple Mono: 带 Nerd Font 图标 + CJK 中文字形
      maple-mono.NF-CN
    ];
    fontDir.enable = true;
  };

  fonts.fontconfig = {
    defaultFonts = {
      serif = [ "Noto Serif CJK SC" "Noto Serif" ];
      sansSerif = [ "Noto Sans CJK SC" "Noto Sans" ];
      monospace = [ "Maple Mono NF CN" "Noto Sans Mono CJK SC" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
