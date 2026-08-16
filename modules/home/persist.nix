# 家目录持久化(用户级)—— 编译链缓存/配置迁移到 @persist 并符号链接
# @root 会被快照回滚/重建, @persist 由 snapper 保护 (跨重建保留)。
# ~/.cc-switch 例外 (cc-switch 拒绝符号链接), 由 nixos/persist.nix bind mount 处理。
{ lib, ... }:
{
  home.activation.persistHomeDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PERSIST_HOME="/persist/home/$(whoami)"
    if [ ! -d "$PERSIST_HOME" ] || [ ! -w "$PERSIST_HOME" ]; then
      echo "警告: $PERSIST_HOME 不可用, 跳过持久化"
      exit 0
    fi
    # 编译链缓存/配置 + 应用 state (大、下载慢, 重装后保留): maven/gradle/rust/go/node/pnpm/npm/uv
    # .local/state: 应用运行时状态 (niri 分辨率、noctalia settings 等)
    for dir in .claude .m2 .gradle .rustup .cargo .nvm .local/state .local/share/nvm go .local/share/pnpm .npm .cache/uv; do
      src="$HOME/$dir"
      dst="$PERSIST_HOME/$dir"
      if [ -L "$src" ] && [ "$(readlink "$src")" = "$dst" ]; then
        : # 已是正确链接
      elif [ -e "$src" ]; then
        echo "==> 迁移 $src -> $dst"
        mkdir -p "$(dirname "$dst")"
        mv "$src" "$dst"
        mkdir -p "$(dirname "$src")"
        ln -s "$dst" "$src"
      else
        mkdir -p "$dst"
        mkdir -p "$(dirname "$src")"
        ln -s "$dst" "$src"
      fi
    done
  '';
}
