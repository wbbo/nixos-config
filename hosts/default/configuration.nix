# host: default (分发模板主机)
# 主机入口 —— 导入系统/硬件模块和 Home Manager。
{ config, lib, inputs, ... }:

{
  imports = [
    # 硬件扫描结果: initrd/kernel 模块 / 文件系统支持
    # 由 install.sh 调用 nixos-generate-config --root /mnt 自动生成
    # fileSystems / swapDevices 由 disko 模块根据 disks.nix 自动生成
    ./hardware-configuration.nix

    # disko —— 声明式磁盘配置, 生成 fileSystems / swapDevices
    inputs.disko.nixosModules.disko
    ./disks.nix

    # sops-nix —— 秘密管理 (age 解密 → /run/secrets/)
    inputs.sops-nix.nixosModules.sops

    # Home Manager 的 NixOS 模块(来自 flake input)
    inputs.home-manager.nixosModules.home-manager

    # impermanence —— 声明式持久化; 须在 home-manager NixOS 模块之后导入,
    # 它检测到 home-manager.sharedModules 选项后自动给 HM 注入 home.persistence
    inputs.impermanence.nixosModules.impermanence

    # 系统级模块集合
    ../../modules/nixos

    # 本地定制 (gitignored): hosts/default/local.nix
    # 每台机器在这里覆盖 hostName / mainUser 等, 不入库 (类似 secrets 的本地化方式)
  ] ++ lib.optional (builtins.pathExists ./local.nix) ./local.nix;

  # Home Manager 集成:复用系统 nixpkgs,用户级包走 user profile
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    # mainUser 通过 extraSpecialArgs 传给 Home Manager 模块(modules/home/*)
    extraSpecialArgs = {
      inherit (inputs) noctalia;
      mainUser = config.mainUser;
    };
    users.${config.mainUser} = import ../../modules/home;
  };

  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.05";
}
