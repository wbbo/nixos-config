# 应用启动器 fuzzel(Catppuccin Mocha)
{ pkgs, ... }:
{
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=12";
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
