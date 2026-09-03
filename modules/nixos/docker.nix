# Docker 开发环境 —— 系统服务 + CLI + 数据持久化到 @persist
# docker 组已由 users.nix 的 extraGroups 统一管理, 此处不重复。
{ pkgs, ... }:
{
  virtualisation.docker = {
    enable = true;
    # 镜像/容器数据在 @persist (data-root), 跨重建保留 (不需要时不重新 pull)
    extraOptions = "--data-root /persist/docker";
  };

  environment.systemPackages = with pkgs; [
    docker-compose
  ];
}
