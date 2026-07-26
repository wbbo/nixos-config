# 字体:中文 + 英文 + 等宽(Nerd Font)+ Emoji
{ pkgs, ... }:
{
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      # Nerd Font:终端图标。26.05 用新的 nerd-fonts 集合(按字体拆分)
      nerd-fonts.jetbrains-mono
    ];
    fontDir.enable = true;
  };

  fonts.fontconfig = {
    defaultFonts = {
      serif = [ "Noto Serif CJK SC" "Noto Serif" ];
      sansSerif = [ "Noto Sans CJK SC" "Noto Sans" ];
      monospace = [ "JetBrainsMono Nerd Font" "Noto Sans Mono CJK SC" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
