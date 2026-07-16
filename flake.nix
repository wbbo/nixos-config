{
  description = "NixOS 26.05 + Niri + Noctalia Shell 桌面配置 (可分发模板)";

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

    # disko —— 声明式分区 & 格式化 (替代 install.sh 的手工分区逻辑)
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix —— 秘密管理 (age 加密, secrets 签入 git, 部署时主机密钥解密)
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: let
    # 固定主机名 —— 仅决定 flake 输出名 (nixosConfigurations.<hostName>) 与 networking.hostName 默认值。
    # 实际主机名/用户名在 hosts/<hostDir>/local.nix 覆盖 (networking.hostName / mainUser), 无需修改此处。
    hostName = "nixos";
    # 物理主机目录 —— hosts/<hostDir>/ 下的配置目录 (可独立于 hostName 命名)
    hostDir = "default";
  in {
    # disko 包暴露给 install.sh: nix run .#disko 使用 flake.lock 锁定的版本,
    # 避免 github: 引用解析分支时调 GitHub API 触发匿名限流 (Live CD 无 token)
    packages.x86_64-linux.disko = inputs.disko.packages.x86_64-linux.disko;

    nixosConfigurations.${hostName} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        # hostName 经 specialArgs 下发到各模块 (networking.nix 等引用)
        hostName = hostName;
      };
      modules = [
        ./hosts/${hostDir}/configuration.nix
      ];
    };
  };

}
