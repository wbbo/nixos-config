# fcitx5 中文输入法 —— Home Manager 用户配置
# 系统配置见 modules/nixos/ime.nix
{ config, pkgs, lib, ... }: let
  # 注入雾凇拼音 (rime-ice) 词库，替代 fcitx5-chinese-addons
  # rimeDataPkgs 按顺序合并: rime-ice 在后可覆盖 rime-data 同名文件
  fcitx5Rime = pkgs.fcitx5-rime.override {
    rimeDataPkgs = [ pkgs.rime-data pkgs.rime-ice ];
  };
  fcitx5Pkgs = pkgs.qt6Packages.fcitx5-with-addons.override {
    addons = [
      fcitx5Rime                    # Rime 引擎 + 雾凇拼音词库
      pkgs.qt6Packages.fcitx5-qt    # fcitx5 Qt immodule
    ];
  };
in
{
  # fcitx5 包放入系统包(由 Home Manager 管理)
  home.packages = [ fcitx5Pkgs ];

  # 环境变量(所有 Wayland 应用生效, Niri 环境变量在 niri config.kdl 也有)
  home.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    SDL_IM_MODULE = "fcitx";
    GLFW_IM_MODULE = "ibus"; # fcitx5 兼容 ibus
    QT_QPA_PLATFORM = "wayland;xcb";
    INPUT_METHOD = "fcitx";
  };

  # 雾凇拼音 Rime 配置
  # - __include 加载雾凇默认方案(词库/双拼/schema/标点/Lua 脚本)
  # - 默认 schema 为 rime_ice (雾凇拼音全拼)
  xdg.dataFile."fcitx5/rime/default.custom.yaml".text = builtins.toJSON {
    patch = {
      __include = "rime_ice_suggestion:/";
      schema_list = [{
        schema = "rime_ice";
      }];
      menu.page_size = 9;
      switcher.hotkeys = [ "Control+grave" ];
    };
  };

  # rime_ice 雾凇拼音默认简体中文
  xdg.dataFile."fcitx5/rime/rime_ice.custom.yaml".text = ''
    patch:
      switches:
        - name: traditionalization
          reset: 0  # 默认简体 (0 = 简)
  '';

  # fcitx5 自动激活 rime —— 将 rime 注册到 Input Method 列表
  # 没有此文件则首次使用需手动在 fcitx5 config GUI 里添加 Rime
  # force = true: 允许覆盖 fcitx5 GUI 手动生成的 profile (避免 collide)
  xdg.configFile."fcitx5/profile" = {
    force = true;
    text = ''
      [Groups/0]
      Name=Default
      Default Layout=us
      DefaultIM=rime

      [Groups/0/Items/0]
      Name=keyboard-us
      Layout=

      [Groups/0/Items/1]
      Name=rime
      Layout=

      [GroupOrder]
      0=Default
    '';
  };
}
