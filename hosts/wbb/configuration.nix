# host: wbb
# 主机入口 —— 导入系统/硬件模块和 Home Manager。
{ inputs, ... }:

{
  imports = [
    # 硬件扫描结果: initrd 模块 / CPU 微码 / fileSystems
    # 由 install.sh 调用 nixos-generate-config --root /mnt 自动生成
    ./hardware-configuration.nix

    # Home Manager 的 NixOS 模块(来自 flake input)
    inputs.home-manager.nixosModules.home-manager

    # 系统级模块集合
    ../../modules/nixos
  ];

  # Home Manager 集成:复用系统 nixpkgs,用户级包走 user profile
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit (inputs) noctalia; };
    users.wbb = import ../../modules/home;
  };

  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.05";
}
