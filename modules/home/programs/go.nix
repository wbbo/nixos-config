# Go 开发环境
{ pkgs, ... }:
{
  home.packages = with pkgs; [ go ];
}
