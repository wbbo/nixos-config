# Node 开发环境 —— 系统 nodejs(npm 自带) + pnpm + nvm 多版本管理
# nvm 是 bash 实现, 用 nvm.fish 插件接入 fish (conf.d 自动加载)
# nvm/nvm.fish 补装走用户级 systemd 服务 (同 claude.nix): linger 常驻开机即异步拉起,
# 不阻塞启动。曾为 HM 激活钩子 —— boot 期串行下载拖慢激活。
{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    nodejs
    pnpm_10  # pnpm 11 与 nodejs-slim 24 有 nixpkgs 输出 bug, 用 10
  ];

  systemd.user.services.nvm-install = {
    Unit.Description = "补装 nvm + nvm.fish (缺失才下载; 已装秒退)";
    Service = {
      Type = "oneshot";
      # 两个 tarball 各 ~1-2MB, 正常数十秒; 留余量
      TimeoutStartSec = "3min";
      ExecStart = pkgs.writeShellScript "install-nvm" ''
        # 管道失败可见: writeShellScript 无 set -e/pipefail (curl|tar 竞态)
        set -o pipefail
        export PATH="${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.curl}/bin:$PATH"
        # 两者都齐才秒退; 任一缺失只补缺的那个 (幂等, rebuild 会 restart 重跑)
        NEED_NVM=0; NEED_FISH=0
        [ -f "$HOME/.nvm/nvm.sh" ] || NEED_NVM=1
        [ -f "$HOME/.config/fish/functions/nvm.fish" ] || NEED_FISH=1
        [ "$NEED_NVM$NEED_FISH" = "00" ] && exit 0
        # mihomo 代理探测 (127.0.0.1:7890 mix-port): github 直连时通时不通。
        # 重试 3 次 x2s (末次成功不再多等) —— linger boot 期 mihomo 偶未就绪
        for i in 1 2 3; do
          if ${pkgs.coreutils}/bin/timeout 1 ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/127.0.0.1/7890' 2>/dev/null; then
            export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
            break
          fi
          [ "$i" = 3 ] || sleep 2
        done
        FAIL=0
        if [ "$NEED_NVM" = 1 ]; then
          echo "==> 后台补装 nvm (node 版本管理器)"
          mkdir -p "$HOME/.nvm"
          rm -rf /tmp/nvm-master
          # --retry-all-errors: DNS 未就绪 (curl 6) 也重试; 失败置 FAIL 使 unit 呈
          # failed (systemctl --user --failed 可见), rebuild 会 restart 本服务重试
          ${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 30 --retry 3 --retry-delay 3 --retry-max-time 60 --retry-all-errors -fsSL \
            https://github.com/nvm-sh/nvm/archive/refs/heads/master.tar.gz \
            | tar xzf - -C /tmp 2>/dev/null \
            && cp -r /tmp/nvm-master/* "$HOME/.nvm/" 2>/dev/null \
            && rm -rf /tmp/nvm-master \
            || { echo "警告: nvm 安装失败"; FAIL=1; }
          rm -rf /tmp/nvm-master
        fi
        if [ "$NEED_FISH" = 1 ]; then
          echo "==> 后台补装 nvm.fish (fish 集成, conf.d + functions)"
          mkdir -p "$HOME/.config/fish/conf.d" "$HOME/.config/fish/functions"
          rm -rf /tmp/nvm.fish-*
          ${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 30 --retry 3 --retry-delay 3 --retry-max-time 60 --retry-all-errors -fsSL \
            https://github.com/jorgebucaran/nvm.fish/archive/refs/heads/master.tar.gz \
            | tar xzf - -C /tmp 2>/dev/null \
            && cp /tmp/nvm.fish-*/conf.d/*.fish "$HOME/.config/fish/conf.d/" 2>/dev/null \
            && cp /tmp/nvm.fish-*/functions/*.fish "$HOME/.config/fish/functions/" 2>/dev/null \
            && rm -rf /tmp/nvm.fish-* \
            || { echo "警告: nvm.fish 安装失败"; FAIL=1; }
          rm -rf /tmp/nvm.fish-*
        fi
        [ "$FAIL" = 0 ] || { echo "重试: ./build.sh 或 systemctl --user restart nvm-install"; exit 1; }
      '';
    };
    Install.WantedBy = [ "default.target" ];
  };
}
