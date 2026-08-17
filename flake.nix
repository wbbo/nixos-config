{
  description = "NixOS 26.05 + Niri + Noctalia Shell 桌面配置 (可分发模板)";

  inputs = {
    # NixOS 26.05 发行分支 (社区标准: github tarball + netrc 三条目认证, 见 nix.nix)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia Shell —— 面板/通知/启动器/锁屏/壁纸(替代 waybar+mako+swaybg)
    # quickshell 由 noctalia 内部管理,无需在此声明
    # 跟踪 main 分支, 升级: nix flake update noctalia
    # (分支解析走 api.github.com, 凭据由 github-netrc 的 api.github.com 条目提供,
    #  见 secrets.template.yaml; 安装期用 GITHUB_TOKEN 环境变量, 见 install.sh)
    # 注意: 不 follow 我们的 nixpkgs —— Noctalia 官方用 nixos-unstable 构建,
    # follows 到 26.05 会导致旧 quickshell/luau 编译出插件 API 只支持 3-4
    # (mpvpaper 插件需 API 9)。保持官方 unstable 才能完整支持插件系统。
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
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
