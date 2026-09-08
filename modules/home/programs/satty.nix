# satty 配置部署 —— 只部署最小配置 (中文渲染修复, 详见 satty-config.toml)
{ lib, ... }:
{
  xdg.configFile."satty/config.toml".source = ./satty-config.toml;
}
