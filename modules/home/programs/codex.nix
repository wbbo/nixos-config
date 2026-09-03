# codex —— OpenAI Codex CLI (官方 install.sh 安装)
# 装到 ~/.local/bin, 由 fish.nix 的 fish_add_path 纳入 PATH。
# 布局与 claude native installer 同构: 版本化目录
#   ~/.codex/packages/standalone/releases/<ver> + current 软链,
# 自带 `codex update` 自更新。
# 补装走用户级 systemd 服务 (同 claude.nix): linger 常驻 user manager 开机即异步拉起, 不阻塞启动。
{ pkgs, ... }:
{
  systemd.user.services.codex-install = {
    Unit.Description = "补装 codex CLI (官方 install.sh, 缺失才下载; 已装秒退)";
    Service = {
      Type = "oneshot";
      # 内层最坏 ~3min (curl retry 60s + timeout 120 + 探测), 留余量
      TimeoutStartSec = "5min";
      ExecStart = pkgs.writeShellScript "install-codex" ''
        # 管道失败可见: writeShellScript 无 set -e/pipefail, curl 失败时管道
        # 经 bash (空 stdin 退 0) 会静默成功, 必须显式 pipefail
        set -o pipefail
        # 已装则秒退 (幂等, rebuild 会 restart 本服务重跑)
        if [ -x "$HOME/.local/bin/codex" ]; then
          exit 0
        fi
        # 服务环境 PATH 精简: 官方脚本是 POSIX sh 但依赖 awk/grep/sed 等,
        # 必须补 gawk; tar/gzip 备用 (部分下载分支解压)
        export PATH="${pkgs.gawk}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.curl}/bin:$PATH"
        # 服务无 TTY, 跳过 PATH 冲突等交互询问
        export CODEX_NON_INTERACTIVE=true
        echo "==> 后台补装 codex (官方 install.sh)"
        # 现场诊断: 断链/目录被清/HOME 异常一眼可见
        echo "--- HOME=$HOME"; ls -la "$HOME/.local/bin/" 2>/dev/null | head -5 || true
        ls -la "$HOME/.codex/packages/standalone/releases/" 2>/dev/null | head -5 || true
        # mihomo 代理探测 (127.0.0.1:7890 mix-port): 直连不可达的环境 (chatgpt.com 被墙)。
        # 重试 3 次 x2s (末次成功不再多等) —— linger boot 期 mihomo 偶未就绪
        for i in 1 2 3; do
          if ${pkgs.coreutils}/bin/timeout 1 ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/127.0.0.1/7890' 2>/dev/null; then
            export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
            break
          fi
          [ "$i" = 3 ] || sleep 2
        done
        # 脚本内部优先 releases.openai.com CDN (TUN 下连通性优于 github),
        # 资产约 95MB、其自身单资产超时 300s; 外层 curl 仅拉脚本本体 (~30KB)。
        # --retry-all-errors: DNS 未就绪 (curl 6) 也重试; timeout 120 兜底内层;
        # 失败 exit 1 使 unit 呈 failed (systemctl --user --failed 可见),
        # rebuild 会 restart 本服务重试
        ${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 30 --retry 3 --retry-delay 3 --retry-max-time 60 --retry-all-errors -fsSL \
          https://chatgpt.com/codex/install.sh | ${pkgs.coreutils}/bin/timeout 120 ${pkgs.bash}/bin/bash \
          || { echo "警告: codex 安装失败 (journalctl --user -u codex-install); 重试: ./scripts/rebuild.sh 或 systemctl --user restart codex-install"; exit 1; }
      '';
    };
    Install.WantedBy = [ "default.target" ];
  };
}
