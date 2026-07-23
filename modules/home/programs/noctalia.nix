# noctalia 壁纸配置
# 通过 xdg.configFile 直接将配置写入 ~/.local/state/noctalia/settings.toml
{ ... }:
{
  xdg.configFile."noctalia/config.toml".text = ''
    [wallpaper]
    directory = "/home/wbb/wallpaper"
  '';
}
