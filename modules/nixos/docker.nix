# Docker 开发环境 —— 系统服务 + CLI + 数据持久化到 @persist
# docker 组已由 users.nix 的 extraGroups 统一管理, 此处不重复。
{ config, pkgs, ... }:
{
  virtualisation.docker = {
    enable = true;
    # 按需启动 (socket 激活): docker.service 不随开机启动 —— 无容器/镜像且
    # 无人使用的机器上零常驻 (实测 dockerd 113M + 20 进程; 2026-09-26 起)。
    # 任意 docker 命令连接 /run/docker.sock 时由 systemd 自动唤醒 dockerd
    # (docker.socket 常驻, 一个监听 socket 近零成本)。
    # 唤醒后的释放由下方 docker-idle-stop 定时器负责 (上游无内建空闲退出)。
    # 例外: 若有 --restart=always 的容器需开机自启, 改回 enableOnBoot = true。
    enableOnBoot = false;
    # 镜像/容器数据在 @persist (data-root), 跨重建保留 (不需要时不重新 pull)
    extraOptions = "--data-root /persist/docker";
  };

  # 空闲自动释放: dockerd 无内建空闲退出 (与 libvirtd 的 --timeout 不同),
  # 用 timer 每 5 分钟检查一次, 满足"无运行中容器且无活跃客户端连接"时停止
  # dockerd (containerd 随 docker 的 PartOf 关系一并停止, 实测确认); 下次
  # docker 命令经 socket 激活自动唤醒, 无缝。
  # 判据说明:
  #   - 有运行中容器 → 不动 (容器必须保持运行; stop 掉的容器不影响 —— 它是
  #     磁盘状态, docker start 会先唤醒 daemon)
  #   - 有活跃客户端连接 (build/exec/events 等进行中的长连接) → 不动
  #   - dockerd 未运行 → 立即退出 (且不可调用 docker 命令 —— 会唤醒它)
  systemd.services.docker-idle-stop = {
    description = "Stop Docker daemon when idle (no running containers/clients)";
    path = [ pkgs.iproute2 config.virtualisation.docker.package ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "docker-idle-stop" ''
        systemctl is-active --quiet docker || exit 0
        if [ -n "$(docker ps -q 2>/dev/null)" ]; then exit 0; fi
        if ss -xH state established 2>/dev/null | grep -q 'docker.sock'; then exit 0; fi
        echo "docker idle: no running containers or active clients, stopping dockerd (auto-wakes on next use)"
        systemctl stop docker
      '';
    };
  };
  systemd.timers.docker-idle-stop = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5"; # 每 5 分钟; 未使用 dockerd 时检查本身开销近零
      Persistent = false;
    };
  };

  environment.systemPackages = with pkgs; [
    docker-compose
  ];
}
