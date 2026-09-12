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
      # STIX Two Math: 数学符号字体。WPS 启动自检会检查公式符号字体, 缺失时
      # 弹 "Some formula symbols might not be displayed correctly" —— 系统原先
      # 把 Symbol/Wingdings 错误映射到 Noto Sans CJK SC (字形对不上), 这里补
      # 一个真正含数学符号的字体, 并由下面 localConf 做字体名别名。
      stix-two
    ];
    fontDir.enable = true;

    fontconfig = {
      defaultFonts = {
        serif = [ "Noto Serif CJK SC" "Noto Serif" ];
        sansSerif = [ "Noto Sans CJK SC" "Noto Sans" ];
        monospace = [ "Maple Mono NF CN" "Noto Sans Mono CJK SC" ];
        emoji = [ "Noto Color Emoji" ];
      };
      # 注: 符号字体别名 (Symbol / MT Extra → STIX Two Math) 刻意不在此处做。
      # 本模块的 localConf 会生成到 /etc/fonts/local.conf, 由 conf.d/51-local.conf
      # 引入 —— 优先级 51, 会被后续规则 (60-latin.conf 等) 覆盖, 实测写了不生效
      # (Symbol 仍解析到 Noto Sans CJK SC)。改放用户级 fontconfig, 优先级最高,
      # 见 modules/home/fonts.nix。stix-two 字体本身仍由上面的 packages 提供。
    };
  };
}
