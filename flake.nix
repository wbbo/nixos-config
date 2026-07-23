{
  description = "NixOS 26.05 + Niri + Noctalia Shell 桌面配置 (host: wbb)";

  inputs = {
    # NixOS 26.05 发行分支
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia Shell —— 面板/通知/启动器/锁屏/壁纸(替代 waybar+mako+swaybg)
    # quickshell 由 noctalia 内部管理,无需在此声明
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.wbb = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/wbb/configuration.nix
      ];
    };
  };
}
