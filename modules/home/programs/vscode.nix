# VS Code —— 纯 Wayland 原生运行 (Ozone 后端)
{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    # 无 X11, 强制 Ozone Wayland 后端
    package = pkgs.vscode.override {
      commandLineArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland";
    };
  };
}
