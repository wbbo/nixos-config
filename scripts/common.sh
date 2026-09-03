#!/usr/bin/env bash
# 公共函数库: install.sh / scripts/adapt-hardware.sh / build.sh source 复用。
# 依赖调用者先定义 SCRIPT_DIR (仓库根目录绝对路径), 再 source 本文件:
#   source "$SCRIPT_DIR/scripts/common.sh"

# 彩色输出 (统一三个脚本风格)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
die()  { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }

# 从 flake.nix 解析主机名 (let hostName, 覆盖 default)
# 注意 || true: set -euo pipefail 下 grep 无匹配会让命令替换静默终止整个脚本,
# 导致 :-nixos 兜底不可达
host_name() {
  local n
  n="$(grep -oP 'hostName = "\K[^"]+' "$SCRIPT_DIR/flake.nix" 2>/dev/null | head -1 || true)"
  echo "${n:-nixos}"
}

# 从 flake.nix 解析主机目录 (let hostDir, 覆盖 default)
host_dir() {
  local d
  d="$(grep -oP 'hostDir = "\K[^"]+' "$SCRIPT_DIR/flake.nix" 2>/dev/null | head -1 || true)"
  echo "${d:-default}"
}

# 替换文件内容但永不改变其属主/属组 (无论 root 还是普通用户运行):
# 已存在的文件直接截断写同一个 inode, 属主不变; 文件不存在时新建后对齐
# 仓库根目录属主 (install.sh 全新安装场景, 其仓库属 root)。内容从 stdin 读入。
# 替代 sed -i / cat >: 二者经"临时文件 + rename"会换 inode, 属主随运行者漂移
# —— root 跑过一次适配后, 普通用户 rebuild 就"权限不够"。
replace_preserving_owner() {
  local file="$1" owner=""
  [ -e "$file" ] && owner="$(stat -c %u:%g "$file" 2>/dev/null || true)"
  cat > "$file"
  if [ -z "$owner" ]; then
    owner="$(stat -c %u:%g "${SCRIPT_DIR:-.}" 2>/dev/null || echo 0:0)"
    chown "$owner" "$file" 2>/dev/null || true
  fi
}

# sed -E 就地替换 (保属主): 先把 sed 输出完整落到临时文件, 再经
# replace_preserving_owner 写回目标。不能直接 `sed "$file" | replace "$file"`:
# 管道两侧并发, 左 sed 读目标、右 cat 截断目标, 顺序无保证 —— 内存紧张 (Live CD
# 安装期) 时 cat 的 O_TRUNC 可能先于 sed 的 open+read, 目标被清成 0 字节
# (boot.nix 曾因此被清空, nixos-install 求值报 syntax error)。临时文件中转后,
# 写回时数据已就绪且不再读目标, 竞态彻底消除。
sed_replace() {
  local expr="$1" file="$2" tmp rc
  tmp="$(mktemp "${TMPDIR:-/tmp}/sed-replace.XXXXXX")" || return 1
  if sed -E "$expr" "$file" >"$tmp"; then
    replace_preserving_owner "$file" <"$tmp"
    rc=$?
  else
    rc=1
  fi
  rm -f "$tmp"
  return "$rc"
}

# 注入 resume_offset 数值到 boot.nix (adapt-hardware.sh 常规 rebuild 与
# install.sh disko 后补探共用): 仅替换数值, 其余内容不动; 注入失败非零退出,
# 由调用方决定降级方式 (set -e 环境下勿裸调用)
inject_resume_offset() {
  local offset="$1" cfg="$SCRIPT_DIR/modules/nixos/boot.nix"
  sed_replace "s|resume_offset=[0-9]+|resume_offset=${offset}|" "$cfg"
}

# 还原 adapt-hardware.sh 产生的配置改动 (hardware-configuration.nix + disks.nix
# + boot.nix 的 resume_offset): 适配是构建期临时状态 (rebuild/install 构建时生效,
# 系统已固化), 完成后还原保持仓库干净 (分发模板语义); 精确限定三个文件,
# 不碰 local.nix 等用户改动。失败时静默保留改动 (便于排障)。
# 属主契约: git restore 只还内容, 部分路径 (过滤器/LFS) 会换 inode 让属主漂移;
# 逐文件记录 restore 前属主并原样恢复 —— 无论运行者是 root 还是普通用户,
# 三个文件的属主/属组始终等于 rebuild 开始时的值。
restore_adapt() {
  local dir root_dir f owner
  dir="$(host_dir)"
  root_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  for f in "hosts/${dir}/hardware-configuration.nix" "hosts/${dir}/disks.nix" \
           "modules/nixos/boot.nix"; do
    owner="$(stat -c %u:%g "$f" 2>/dev/null || true)"
    [ -n "$owner" ] || owner="$(stat -c %u:%g "$root_dir" 2>/dev/null || true)"
    git restore --worktree "$f" 2>/dev/null || true
    [ -n "$owner" ] && chown "$owner" "$f" 2>/dev/null || true
  done
}
