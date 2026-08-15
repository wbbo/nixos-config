# Node 开发环境 —— 系统 nodejs(npm 自带) + pnpm + nvm 多版本管理
# nvm 是 bash 实现, 用 nvm.fish 插件接入 fish (conf.d 自动加载)
{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    nodejs
    pnpm_10  # pnpm 11 与 nodejs-slim 24 有 nixpkgs 输出 bug, 用 10
  ];

  # nvm + nvm.fish: 仅缺失补装 (curl 下载 tarball, 激活环境无 git)
  home.activation.installNvm = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "$HOME/.nvm/nvm.sh" ]; then
      echo "==> 安装 nvm (node 版本管理器)"
      mkdir -p "$HOME/.nvm"
      rm -rf /tmp/nvm-master
      curl -fsSL https://github.com/nvm-sh/nvm/archive/refs/heads/master.tar.gz 2>/dev/null \
        | tar xz -C /tmp - 2>/dev/null \
        && cp -r /tmp/nvm-master/* "$HOME/.nvm/" 2>/dev/null \
        && rm -rf /tmp/nvm-master \
        || echo "警告: nvm 安装失败(网络?), 下次 switch 重试"
    fi
    if [ ! -f "$HOME/.config/fish/functions/nvm.fish" ]; then
      echo "==> 安装 nvm.fish (fish 集成, conf.d + functions)"
      mkdir -p "$HOME/.config/fish/conf.d" "$HOME/.config/fish/functions"
      rm -rf /tmp/nvm.fish-*
      curl -fsSL https://github.com/jorgebucaran/nvm.fish/archive/refs/heads/master.tar.gz 2>/dev/null \
        | tar xz -C /tmp - 2>/dev/null \
        && cp /tmp/nvm.fish-*/conf.d/*.fish "$HOME/.config/fish/conf.d/" 2>/dev/null \
        && cp /tmp/nvm.fish-*/functions/*.fish "$HOME/.config/fish/functions/" 2>/dev/null \
        && rm -rf /tmp/nvm.fish-* \
        || echo "警告: nvm.fish 安装失败(网络?), 下次 switch 重试"
    fi
  '';
}
