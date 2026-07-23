# Nix 包管理器本身:Flakes、自动 GC、镜像 substituter、unfree 许可
{ ... }:
{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # 教育网镜像优先,官方 cache 兜底
      substituters = [
        "https://mirrors.cernet.edu.cn/nix-channels/store"
        "https://cache.nixos.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        # 教育网镜像复用 cache.nixos.org 的公钥,无需额外条目
      ];
      auto-optimise-store = true;
    };

    # 每周自动清理:删除 7 天前的 generation 与垃圾
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  ### 允许安装 unfree(非自由许可证)软件
  nixpkgs.config.allowUnfree = true;
}
