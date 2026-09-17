# 浏览器 Firefox(Wayland 原生 + Nix 搜索引擎)
{ pkgs, mainUser, ... }:
{
  programs.firefox = {
    enable = true;
    # 中文界面: ⚠ 本选项在当前组合 (HM 26.05 + firefox 155) 下**实测未生效** ——
    # 2026-09-17 核实: 加上后 /nix/store 无 langpack 产物、HM 代际 home-files 与
    # home.file 列表里都没有对应条目、firefox 包内也没有 xpi。保留此行待上游修正,
    # **不要据此以为中文界面已经声明式化**。
    # 现在的中文界面来自 profile 里手工装的 langpack-zh-CN@firefox.mozilla.org.xpi
    # (Firefox 内 AMO 一键装): 随 profile 持久化, 同机重装不丢; 换机/全新安装需
    # 手工再装一次 (或等本选项真正生效)。
    languagePacks = [ "zh-CN" ];
    profiles.${mainUser} = {
      isDefault = true;
      settings = {
        "gfx.webrender.all" = true;
        "browser.startup.homepage" = "about:home";
        "extensions.pocket.enabled" = false;
        "browser.toolbars.bookmarks.visibility" = "newtab";
      };
      search = {
        force = true;
        default = "google";
        engines = {
          "NixOS Options" = {
            urls =
              [{ template = "https://search.nixos.org/options?query={searchTerms}"; }];
            icon =
              "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@no" ];
          };
          "NixOS Packages" = {
            urls = [{
              template = "https://search.nixos.org/packages?query={searchTerms}";
            }];
            icon =
              "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@np" ];
          };
        };
      };
    };
  };
}
