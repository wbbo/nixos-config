# Home Manager 激活钩子每个 switch 强制重跑
# 背景: home-manager-<user>.service 只在其生成内容变化时才被 systemd 重启 ——
# 仅改 secrets.yaml (sops 层, 不参与 HM 求值) 或外部手动修复后跑 switch,
# 激活钩子不会重新评估, installNvm 这类
# "检查外部状态并修复"的钩子 (依赖 $HOME 下文件存在性) 会错过修复窗口
# (曾例: HM 外部装好 cc-switch 后 S3 一直未配置, 2026-08-23 实测踩坑;
#  工具补装 + S3 配置已迁到 cc-switch-install 等用户级服务, 见
#  modules/home/programs/cc-switch.nix, 本脚本 restart 一并覆盖, 见下方)。
# 解法: NixOS activation script 每次 nixos-rebuild switch 无条件执行, 在此
# restart HM 服务 → 全部激活钩子以最新 secrets 重跑 (幂等, 稳态 <1s)。
# - 顺序在 setupSecrets 之后: 否则 secrets 轮换时钩子读到旧值 (同 mihomo.nix 先例)
# - unit 名用 escapeSystemdPath: HM 对用户名如此命名, 含 '-' 会转义为 \x2d
#   (手工拼接会 unit not found 被 || 吞掉, 见 greetd.nix 记录的同款坑)
# - restart 而非 try-restart: try-restart 跳过 failed 状态的 unit,
#   违背"每次 switch 必评估"的语义
# - 代价: HM generation 有变化的 switch 中旧 generation 会被先激活一次
#   (随后 switch-to-configuration 再跑新 generation); 稳态重复 <1s, 可接受
{ config, lib, utils, ... }:
{
  system.activationScripts.home-manager-restart = lib.stringAfter [ "users" "var" "setupSecrets" ] ''
    if [ -x /run/current-system/sw/bin/systemctl ]; then
      /run/current-system/sw/bin/systemctl restart \
        home-manager-${utils.escapeSystemdPath config.mainUser}.service \
        || echo "警告: home-manager-${config.mainUser}.service 重启失败"
      # 工具补装服务 (claude-install 等) 一并重跑: linger 下用户 manager 常驻,
      # oneshot 只在 boot 拉起一次, unit 未变时 switch 不会重启它 —— 不重启则
      # secrets 轮换后 S3 重配 / 网络修复后补装重试都错过。--machine 跨用户
      # 实例 restart; 幂等 (已装秒退)。boot 早期激活先于 logind 拉起 user
      # manager, 故轮询等 user manager 可连再执行 (seq 60 x sleep 0.5 =
      # 上限 30s, 低配机 user manager 冷启动留余量; switch 场景首圈即命中
      # 零等待, 上限再大也不多花一毫秒)。boot 期也保证 restart 成功 ——
      # 重启前刚轮换 secrets 的场景, boot 后期补装即带新 secrets 重配,
      # 不必等下一次 switch。超时仍跳过 (零输出): 此时无需 restart, unit
      # enabled, user manager 就绪时自动拉起补装 (兜底)。
      # socket 探测通过后 restart 仍可能失败: switch 的 systemd reload 阶段
      # 老 user manager socket 断开与新实例 bind 交叠 ("Transport endpoint
      # is not connected")。注意 [ -S ] 只测文件存在, 老实例留下的 socket
      # 文件会造成假阳性 (journal 实测: sleep 2 后重试仍失败) —— 探测必须
      # 用真连接 (systemctl --user list-units)。journal 证实此窗口后
      # systemd 自己拉起补装服务 (Enabled unit); 失败即重试一轮, 仍败才告警
      TOOL_USER_UID=$(/run/current-system/sw/bin/id -u ${config.mainUser} 2>/dev/null || true)
      if [ -n "$TOOL_USER_UID" ]; then
        USERCTL() { /run/current-system/sw/bin/systemctl --user --machine=${config.mainUser}@.host "$@"; }
        # 就绪探测: 真连接 (list-units) 而非 [ -S ] (老实例 socket 文件假阳性),
        # seq 60 x sleep 0.5 = 上限 30s
        SOCK_WAIT() { USERCTL list-units --no-legend --no-pager >/dev/null 2>&1; }
        for _ in $(seq 60); do SOCK_WAIT && break || sleep 0.5; done
        # 补装服务重跑; 撞 systemd reload 窗口失败则等 1s 重试一轮 (见上注释)
        RESTART_INSTALLERS() { USERCTL restart \
          claude-install.service codex-install.service cc-switch-install.service; }
        if SOCK_WAIT && ! RESTART_INSTALLERS; then
          sleep 1; SOCK_WAIT && RESTART_INSTALLERS \
            || echo "警告: 补装服务 restart 失败 (systemd reload 窗口, user units 重载阶段会自动拉起)"
        fi
      fi
    fi
    # 首次安装 (nixos-install chroot) 时无运行中系统, 跳过
  '';
}
