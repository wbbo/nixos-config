# claude (Claude Code) —— Anthropic 官方 native installer 安装
# 装到 ~/.local/bin, 由 fish.nix 的 fish_add_path 纳入 PATH。
# 补装走用户级 systemd 服务: linger 常驻 user manager 开机即异步拉起 (无需登录), 缺失才下载,
# 不阻塞系统启动/登录。曾为 HM 激活钩子 —— boot 期三工具串行下载 + 代理竞态
# 下被墙域名吃满 timeout, 首启卡 HM 单元 2min+ (最坏 5m 超时), 已迁移。
{ pkgs, ... }:
{
  systemd.user.services.claude-install = {
    Unit.Description = "补装 claude CLI (官方 install.sh, 缺失才下载; 已装秒退)";
    Service = {
      Type = "oneshot";
      # 内层最坏 ~3min (curl retry 60s + timeout 120 + 探测), 留余量;
      # 服务超时独立于启动流程, 失败不影响登录
      TimeoutStartSec = "5min";
      ExecStart = pkgs.writeShellScript "install-claude" ''
        # 管道失败可见: writeShellScript 无 set -e/pipefail, curl 失败时管道
        # 经 bash (空 stdin 退 0) 会静默成功, 必须显式 pipefail
        set -o pipefail
        # 已装则秒退 (幂等, rebuild 会 restart 本服务重跑)
        if [ -x "$HOME/.local/bin/claude" ]; then
          exit 0
        fi
        # 服务环境 PATH 精简, install.sh 内部要裸调 curl/wget/tar, 缺失会报
        # "Either curl or wget is required..." 静默失败 —— 显式补齐工具 PATH
        # (tar 解压 gz/zst 资产会 exec 外部 gzip/zstd, 必须一并补)
        export PATH="${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.curl}/bin:${pkgs.jq}/bin:${pkgs.zstd}/bin:$PATH"
        echo "==> 后台补装 claude (官方 install.sh)"
        # 现场诊断: 断链/目录被清/HOME 异常一眼可见
        echo "--- HOME=$HOME"; ls -la "$HOME/.local/bin/" 2>/dev/null | head -5 || true
        ls -la "$HOME/.local/share/claude/versions/" 2>/dev/null | head -5 || true
        # mihomo 代理探测 (127.0.0.1:7890 mix-port): 直连不可达的环境 (claude.ai 被墙)。
        # 重试 3 次 x2s (末次成功不再多等) —— linger boot 期 mihomo 偶未就绪,
        # 1s 放弃即直连被墙域名, 是下载卡满 timeout 的放大器
        for i in 1 2 3; do
          if ${pkgs.coreutils}/bin/timeout 1 ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/127.0.0.1/7890' 2>/dev/null; then
            export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
            break
          fi
          [ "$i" = 3 ] || sleep 2
        done
        # --retry-all-errors: DNS 未就绪 (curl 6) 也重试; 外层 curl 限脚本本体 ~60s,
        # install.sh 内部资产下载无超时 → timeout 120 兜底内层; 失败 exit 1 使 unit
        # 呈 failed (systemctl --user --failed 可见), rebuild 会 restart 本服务重试
        ${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 30 --retry 3 --retry-delay 3 --retry-max-time 60 --retry-all-errors -fsSL \
          https://claude.ai/install.sh | ${pkgs.coreutils}/bin/timeout 120 ${pkgs.bash}/bin/bash \
          || { echo "警告: claude 安装失败 (journalctl --user -u claude-install); 重试: ./scripts/rebuild.sh 或 systemctl --user restart claude-install"; exit 1; }
      '';
    };
    Install.WantedBy = [ "default.target" ];
  };
}
