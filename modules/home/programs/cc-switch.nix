# cc-switch —— Claude Code 配置切换 + 用量查询 CLI (官方 install.sh 安装)
# 装到 ~/.local/bin, 由 fish.nix 的 fish_add_path 纳入 PATH。
# 补装走用户级 systemd 服务 (同 claude.nix): linger 常驻 user manager 开机即异步拉起, 不阻塞启动。
# S3 云同步凭据走 sops (secrets.nix 声明), 安装段之后幂等重配
# (同一服务内串行执行, 保证二进制就绪后才配置)。
{ pkgs, ... }:
{
  systemd.user.services.cc-switch-install = {
    Unit.Description = "补装 cc-switch CLI + S3 云同步配置 (缺失才下载; 已装秒过安装段)";
    Service = {
      Type = "oneshot";
      # 内层最坏 ~3min (curl retry 60s + timeout 120 + 探测) + S3 配置, 留余量
      TimeoutStartSec = "5min";
      ExecStart = pkgs.writeShellScript "install-cc-switch" ''
        # 管道失败可见: writeShellScript 无 set -e/pipefail, curl 失败时管道
        # 经 bash (空 stdin 退 0) 会静默成功, 必须显式 pipefail
        set -o pipefail
        # 服务环境 PATH 精简, install.sh 内部要裸调 curl + tar 解压 .tar.gz,
        # 缺失会报 "Required command not found: tar" 静默失败 —— 补齐工具 PATH
        # (tar -xzf 还会 exec 外部 gzip, 必须一并补)
        export PATH="${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.curl}/bin:${pkgs.jq}/bin:${pkgs.zstd}/bin:$PATH"
        if [ ! -x "$HOME/.local/bin/cc-switch" ]; then
          echo "==> 后台补装 cc-switch (官方 install.sh)"
          # 现场诊断: 断链/目录被清/HOME 异常一眼可见
          echo "--- HOME=$HOME"; ls -la "$HOME/.local/bin/" 2>/dev/null | head -5 || true
          # mihomo 代理探测 (127.0.0.1:7890 mix-port): 直连不可达的环境 (github 时通时不通)。
          # 重试 3 次 x2s (末次成功不再多等) —— linger boot 期 mihomo 偶未就绪
          for i in 1 2 3; do
            if ${pkgs.coreutils}/bin/timeout 1 ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/127.0.0.1/7890' 2>/dev/null; then
              export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
              break
            fi
            [ "$i" = 3 ] || sleep 2
          done
          # --retry-all-errors: DNS 未就绪 (curl 6) 也重试; 外层 curl 限脚本本体 ~60s,
          # install.sh 内部下载无超时 → timeout 120 兜底内层; 失败 exit 1 使 unit 呈
          # failed (systemctl --user --failed 可见), rebuild 会 restart 本服务重试
          # (安装段失败即退出, 下方 S3 配置不再执行)
          ${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 30 --retry 3 --retry-delay 3 --retry-max-time 60 --retry-all-errors -fsSL \
            https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | ${pkgs.coreutils}/bin/timeout 120 ${pkgs.bash}/bin/bash \
            || { echo "警告: cc-switch 安装失败 (journalctl --user -u cc-switch-install); 重试: ./scripts/rebuild.sh 或 systemctl --user restart cc-switch-install"; exit 1; }
        fi

        # S3 云同步配置 (Cloudflare R2): 凭据 + bucket/endpoint 都从 sops 解密
        # (/run/secrets, owner=mainUser, 用户服务可读), 幂等重配。
        # NOTE: secret 经 argv 传入, 窗口内本机 ps 可见 —— 单用户桌面机接受此取舍
        CC_SWITCH="$HOME/.local/bin/cc-switch"
        S3_AK="/run/secrets/cc-switch-s3-access-key-id"
        S3_SK="/run/secrets/cc-switch-s3-secret-access-key"
        S3_BUCKET="/run/secrets/cc-switch-s3-bucket"
        S3_ENDPOINT="/run/secrets/cc-switch-s3-endpoint"
        if [ -x "$CC_SWITCH" ] && [ -r "$S3_AK" ] && [ -r "$S3_SK" ] && [ -r "$S3_BUCKET" ] && [ -r "$S3_ENDPOINT" ]; then
          echo "==> 配置 cc-switch S3 云同步"
          "$CC_SWITCH" config s3 set \
            --region auto \
            --bucket "$(cat "$S3_BUCKET")" \
            --access-key-id "$(cat "$S3_AK")" \
            --secret-access-key "$(cat "$S3_SK")" \
            --endpoint "$(cat "$S3_ENDPOINT")" \
            --enable \
            || echo "警告: cc-switch S3 配置失败"
        fi
      '';
    };
    Install.WantedBy = [ "default.target" ];
  };
}
