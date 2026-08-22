# cc-switch —— Claude Code 配置切换 + 用量查询 CLI (官方 install.sh 安装)
# 装到 ~/.local/bin, 由 fish.nix 的 fish_add_path 纳入 PATH。
# 激活钩子: 仅缺失才补装, 失败不阻断 switch。
# S3 云同步凭据走 sops (secrets.nix 声明), 安装后自动 config s3 set。
{ lib, pkgs, ... }:
{
  home.activation.installCcSwitch = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.local/bin/cc-switch" ]; then
      echo "==> 安装 cc-switch (官方 install.sh)"
      # 超时必加: greetd 排队等 home-manager 激活, curl 吊死会拖慢登录 (HM 单元超时 5m);
      # bash 同样用绝对路径 (activation PATH 也不含它)
      ${pkgs.curl}/bin/curl --connect-timeout 5 --max-time 30 -fsSL \
        https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | ${pkgs.bash}/bin/bash \
        || echo "警告: cc-switch 安装失败(网络?), 可手动: curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash"
    fi
  '';

  # S3 云同步配置 (Cloudflare R2): 凭据 + bucket/endpoint 都从 sops 解密 (/run/secrets)
  # 激活时 PATH 不含 ~/.local/bin, 用完整路径调用
  # NOTE: secret 经 argv 传入, 激活窗口内本机 ps 可见 —— 单用户桌面机接受此取舍
  home.activation.configureCcSwitchS3 = lib.hm.dag.entryAfter [ "installCcSwitch" ] ''
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
}
