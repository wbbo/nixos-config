# 系统级模块集合 —— 主机通过 `imports = [ ../../modules/nixos ]` 引入。
{ ... }:
{
  imports = [
    ./bootloader.nix
    ./boot.nix
    ./nix.nix
    ./networking.nix
    ./locale.nix
    ./ime.nix
    ./users.nix
    ./hardware.nix
    ./sound.nix
    ./fonts.nix
    ./services.nix
    ./greetd.nix
    ./snapper.nix
    ./desktop.nix
    ./packages.nix
  ];
}
