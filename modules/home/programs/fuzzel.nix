# fuzzel —— 通用选择器 (--dmenu 模式), 供 res-menu(显示设置)两级菜单使用。
# 应用启动器已由 Noctalia launcher (Mod+Space) 承担, 不再作为独立启动器。
# 样式 (Catppuccin Mocha) 同时作用于 dmenu 弹出菜单。
{ pkgs, ... }:
{
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "Maple Mono NF CN:size=12";
        terminal = "${pkgs.kitty}/bin/kitty -e";
        prompt = "❯ ";
        icons-enabled = true;
        horizontal-pad = 20;
        vertical-pad = 14;
        inner-pad = 6;
        lines = 12;
        width = 40;
        dpi-aware = "no";
      };
      colors = {
        background = "1e1e2eff";
        text = "cdd6f4ff";
        match = "89b4faff";
        selection = "313244ff";
        selection-text = "cdd6f4ff";
        selection-match = "89b4faff";
        border = "89b4faff";
      };
      border = {
        radius = 10;
        width = 2;
      };
    };
  };
}
