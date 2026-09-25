# pigma —— 终端 TUI 网易云音乐客户端 (Rust/Ratatui, 非 Electron)
# nixpkgs 未收编, 以 rustPlatform.buildRustPackage 从 fork 构建:
# - 音频 rodio → cpal → 动态链接 libasound.so.2: buildInputs 补 alsa-lib
#   (pkg-config 供 alsa-sys 探测), Nix rpath 机制保证运行时解析 ——
#   这也是不能裸 `cargo install` 的原因 (NixOS 无 FHS, 产物缺 libasound);
# - 播放输出走 ALSA default 设备, 实际由 pipewire-alsa 接管;
# - TLS 为 rustls (ring), 无 OpenSSL 依赖;
# - 字体要求 Nerd Font, 默认终端字体 Maple Mono NF CN 已满足。
#
# 源用 fork (wbbo/pigma), base = akirco/pigma main@21c380d (v0.2.14 后未发
# tag 的 HEAD, 2026-09-13) + 4 个修复 commit (2026-09-25 固化, 原 postPatch
# 补丁随之退役):
#   4019405 删 .cargo/config.toml (强制 lld + x86-64-v3, Nix 沙箱无 lld 链接失败)
#   8006710 折叠 Cargo.toml 跨行 inline table (TOML 1.0 非法, 新 cargo 拒解析)
#   d2e8e21 debug 日志多字节 UTF-8 边界截断 panic (切"收藏的歌单"闪退)
#   2447e4e y7dl submodule 指向 wbbo/y7dl@08c63e6 (同款 TOML 修复,
#           .gitmodules 同步改; 曾拼错 gitlink 全量 SHA 致 fetchSubmodules
#           "not our ref", amend 修正 —— 训: 短 SHA 必须实测补全, 不许手拼)
#   eb83bde #88 修复升级: get().unwrap_or() 全文兜底改为 debug_truncate
#           helper (最近字符边界截断, debug 日志体积有界)
# 上游出新 tag 时可在 fork 上 rebase, 或把 owner 换回 akirco 并恢复 postPatch。
# 注: 曾内置 pigma-mpris 桥 (轮询 status --json 发布 MPRIS 供 Noctalia
# 媒体组件识别), 已移除恢复默认 —— pigma 无 MPRIS, Noctalia 媒体卡片不
# 显示 pigma, 播放控制走 pigma 自带 TUI/CLI IPC。
{ pkgs, lib, ... }:
let
  pigma = pkgs.rustPlatform.buildRustPackage {
    pname = "pigma";
    version = "0.2.14-unstable-2026-09-25";

    src = pkgs.fetchFromGitHub {
      owner = "wbbo";
      repo = "pigma";
      rev = "eb83bde083a2515d2236eaab9517679be8192924";
      # FOD 输出路径由该 hash 决定: 喂旧 hash 时 store/缓存里同名 outPath 直接
      # 替换旧源码 (不重新拉取), 构建"看似正常"实为旧文件 —— 换 rev 必须同步
      # 换 hash (fakeHash 试错拿 got: 值); 2026-09-25 切 fork 实测踩坑
      hash = "sha256-lX2Y5egavyKIcZmk2ARDnSjMEdCj3tQsBTgA+kbCNPY=";
      # crates/y7dl 是 git submodule (sonar 的路径依赖), GitHub tarball
      # 不含 submodule, 缺它则 cargo 解析 sonar 依赖时报 ENOENT
      # (submodule 现指向 wbbo/y7dl@08c63e6, 见 .gitmodules)
      fetchSubmodules = true;
    };

    cargoHash = "sha256-X4sRm1MJck58/OIGvQjAKmEI1ZqsAms9RK8DMS9+Yls=";

    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.alsa-lib ];

    # 测试触网/需音频设备, 沙箱内必失败
    doCheck = false;

    meta = with lib; {
      description = "Terminal UI NetEase Cloud Music client built with Ratatui";
      homepage = "https://github.com/akirco/pigma";
      license = licenses.asl20;
      mainProgram = "pigma";
      platforms = platforms.linux;
    };
  };
in
{
  home.packages = [ pigma ];
}
