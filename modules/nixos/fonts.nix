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

    fontconfig = {
      defaultFonts = {
        serif = [ "Noto Serif CJK SC" "Noto Serif" ];
        sansSerif = [ "Noto Sans CJK SC" "Noto Sans" ];
        monospace = [ "Maple Mono NF CN" "Noto Sans Mono CJK SC" ];
        emoji = [ "Noto Color Emoji" ];
      };
      # 历史 (2026-09-26 清理): 曾装 stix-two 并在用户级 fontconfig 做
      # Symbol/MT Extra → STIX Two Math 别名 (为消除 WPS 启动自检告警);
      # WPS 弃用后一并移除。踩坑存档: 字体别名写系统级 localConf 会被
      # 60-latin.conf 等后续规则覆盖不生效, 需用户级 ~/.config/fontconfig/。
    };
  };
}
