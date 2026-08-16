# 本机定制: 主机名 / 用户名 (非机密, 纳入版本控制; 接收者改为自己的)
{ lib, ... }:
{
  hostName = "wbb";                 # 主机名
  mainUser = lib.mkForce "wbb";     # 用户名 (覆盖模板默认 user)
  mihomo-ui = "zashboard";          # mihomo WebUI: metacubexd / yacd / zashboard
}
