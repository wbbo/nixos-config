# cc-switch —— Claude Code 配置切换 + 用量查询 CLI (官方 install.sh 安装)
# 装到 ~/.local/bin, 由 fish.nix 的 fish_add_path 纳入 PATH。
# 补装走用户级 systemd 服务 (同 claude.nix): linger 常驻 user manager 开机即异步拉起, 不阻塞启动。
# S3 云同步凭据走 sops (secrets.nix 声明), 安装段之后幂等重配
# (同一服务内串行执行, 保证二进制就绪后才配置)。
#
# proxy 守护自启 (cc-switch-daemon): 开机即拉起 supervisor daemon, daemon 启动时
# 按 db 里 proxy_config 的持久化开关 (proxy enabled / 路由接管) 自动 spawn 对应
# worker —— Claude Code 开箱即有 127.0.0.1:15721 本地代理, 无需先手动跑一次
# cc-switch。生命周期归 systemd (daemon start 前台模式, 上游明示适配 systemd);
# 崩溃自动 Restart=on-failure, 注销不退出 (linger user manager 常驻)。
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
            || { echo "警告: cc-switch 安装失败 (journalctl --user -u cc-switch-install); 重试: ./build.sh 或 systemctl --user restart cc-switch-install"; exit 1; }
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

        # 二进制就绪 → 拉起 proxy daemon (若 ConditionPathExists 曾挡下自启)。
        # 失败不阻断本单元 (daemon 自身 Restart=on-failure 兜底)。
        # ★ --no-block 必需: 同步 start 会与 daemon 的 After=本服务构成死锁
        # (daemon job 等 install 完成, install 卡在等 daemon job)。
        if [ -x "$CC_SWITCH" ]; then
          systemctl --user start cc-switch-daemon.service --no-block || true
        fi
      '';
    };
    Install.WantedBy = [ "default.target" ];
  };

  # proxy supervisor daemon 开机自启 (见文件头注释)。
  # 时序: After cc-switch-install (二进制就绪); 二进制缺失 (install 下载失败/
  # 未跑) 时 ConditionPathExists 挡下, 单元静默跳过不刷失败 —— 由 install
  # 服务成功尾部显式 start 本服务补拉起 (见 install ExecStart 末段)。
  systemd.user.services.cc-switch-daemon = {
    Unit = {
      Description = "cc-switch proxy supervisor daemon (auto-start proxy per persisted config)";
      After = [ "cc-switch-install.service" "home-wbb-.cc\\x2dswitch.mount" ];
      ConditionPathExists = "%h/.local/bin/cc-switch";
    };
    Service = {
      Type = "simple";
      # 旧 daemon 占用 socket/pidfile 时新实例起不来 (rebuild/重启服务场景),
      # ExecStartPre 先停旧的 (stop 优雅收 worker; 无旧实例时非零退出, 已容错)。
      # NOTE: 停旧 daemon 会让本地代理中断 ~1s (新实例随即接管)。
      ExecStartPre = pkgs.writeShellScript "cc-switch-daemon-stop-old" ''
        "$HOME/.local/bin/cc-switch" daemon stop || true
      '';
      # daemon 前台模式: 不 detach, systemd 直接持有主进程 (上游推荐跑 systemd)。
      # 崩溃自动拉起 (on-failure); 用户主动 stop 不复活; 退 1/2/3 (如 socket
      # 仍被占/参数错) 不循环 —— 属需人工排查的状态。
      Restart = "on-failure";
      RestartSec = "5s";
      RestartPreventExitStatus = [ "1" "2" "3" ];
      ExecStart = "%h/.local/bin/cc-switch daemon start";
      # ★ 每次启动显式开启 proxy: daemon 的语义是"优雅关闭 = 放弃接管"
      # (清 takeover 状态并恢复直连配置), 单靠 db 持久状态在 daemon 被
      # stop/start (HM 激活重启、手动重启) 后不会自动恢复 worker。
      # enable 是持久开关 (写 db), worker 由 daemon 按 db 随即拉起。
      # 逐 app 开启 (claude 15721 / codex 15722 / gemini 15723)。
      # socket 未就绪时重试; 彻底失败不阻断 (daemon 存活, 手动可补)。
      ExecStartPost = pkgs.writeShellScript "cc-switch-daemon-enable-proxy" ''
        for app in claude codex gemini; do
          err=""
          ok=""
          for i in 1 2 3 4 5; do
            if err=$("$HOME/.local/bin/cc-switch" proxy enable -a "$app" 2>&1); then
              ok=1
              break
            fi
            sleep 1
          done
          # 失败只汇总一行 (如 gemini 未配 provider 的 "no active provider"),
          # 重试过程的重复报错不刷 journal; 不阻断后续 app / 服务。
          [ -n "$ok" ] || echo "警告: cc-switch proxy enable -a $app 失败: $err"
        done
        exit 0
      '';
    };
    Install.WantedBy = [ "default.target" ];
  };
}
