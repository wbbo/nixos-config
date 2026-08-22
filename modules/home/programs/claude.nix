# claude (Claude Code) —— Anthropic 官方 native installer 安装
# 装到 ~/.local/bin, 由 fish.nix 的 fish_add_path 纳入 PATH。
# 激活钩子: 仅缺失才补装, 失败不阻断 switch。
{ lib, pkgs, ... }:
{
  home.activation.installClaude = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.local/bin/claude" ]; then
      echo "==> 安装 claude (官方 install.sh)"
      # 同 cc-switch.nix: 超时防网络吊死拖登录, curl/bash 绝对路径 (activation PATH 不含)
      ${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 30 -fsSL https://claude.ai/install.sh | ${pkgs.bash}/bin/bash \
        || echo "警告: claude 安装失败(网络?), 可手动: curl -fsSL https://claude.ai/install.sh | bash"
    fi
  '';
}
