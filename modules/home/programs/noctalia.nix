# noctalia 壁纸配置
# xdg.configFile 直接将配置写入 ~/.config/noctalia/config.toml
{ noctalia, ... }:
{
  # 确保壁纸目录存在，并部署默认壁纸
  home.activation.createWallpaperDir = ''
    mkdir -p /home/wbb/wallpaper
    cp -n ${noctalia.packages.x86_64-linux.default}/share/noctalia/assets/noctalia-wallpaper.png /home/wbb/wallpaper/ || true
  '';

  xdg.configFile."noctalia/config.toml".text = ''
    [wallpaper]
    enabled = true
    directory = "/home/wbb/wallpaper"
    fill_color = "#26233a"
    transition_on_startup = true

    [wallpaper.default]
    path = "/home/wbb/wallpaper/noctalia-wallpaper.png"

    # 自动轮换壁纸
    [wallpaper.automation]
    enabled = true
    interval_seconds = 1800
    order = "random"
    recursive = true
  '';
}
