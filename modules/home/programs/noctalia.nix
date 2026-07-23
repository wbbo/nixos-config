# noctalia 壁纸配置
# xdg.configFile 直接将配置写入 ~/.config/noctalia/config.toml
{ ... }:
{
  xdg.configFile."noctalia/config.toml".text = ''
    [wallpaper]
    directory = "/home/wbb/wallpaper"

    # 自动轮换壁纸
    [wallpaper.automation]
    enabled = true
    interval_seconds = 1800
    order = "random"
    recursive = true
  '';
}
