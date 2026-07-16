# 浏览器 Firefox(Wayland 原生 + Nix 搜索引擎)
{ pkgs, mainUser, ... }:
{
  programs.firefox = {
    enable = true;
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
