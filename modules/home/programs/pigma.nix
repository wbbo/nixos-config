# pigma —— 终端 TUI 网易云音乐客户端 (Rust/Ratatui, 非 Electron)
# nixpkgs 未收编, 以 rustPlatform.buildRustPackage 从 fork 构建:
# - 音频 rodio → cpal → 动态链接 libasound.so.2: buildInputs 补 alsa-lib
#   (pkg-config 供 alsa-sys 探测), Nix rpath 机制保证运行时解析 ——
#   这也是不能裸 `cargo install` 的原因 (NixOS 无 FHS, 产物缺 libasound);
# - 播放输出走 ALSA default 设备, 实际由 pipewire-alsa 接管;
# - TLS 为 rustls (ring), 无 OpenSSL 依赖;
# - 字体要求 Nerd Font, 默认终端字体 Maple Mono NF CN 已满足。
#
# 源直接跟上游, v0.2.15 (2026-09-28) 起: 原 fork (wbbo/pigma, base
# akirco/pigma main@21c380d + 4 修复 commit) 的全部修复均已进上游或不再需要:
#   - UTF-8 边界截断 (#88) → 上游 PR #92 (132976b merge 28381e1)
#   - Cargo.toml / y7dl submodule 跨行 inline table → 上游 release 已修,
#     y7dl submodule 已指回 akirco/y7dl
# 仅剩 .cargo/config.toml (强制 lld + x86-64-v3, Nix 沙箱无 lld 链接失败)
# 需 postPatch 删除。
# 注: 曾内置 pigma-mpris 桥 (轮询 status --json 发布 MPRIS 供 Noctalia
# 媒体组件识别), 已移除恢复默认 —— pigma 无 MPRIS, Noctalia 媒体卡片不
# 显示 pigma, 播放控制走 pigma 自带 TUI/CLI IPC。
{ pkgs, lib, ... }:
let
  pigma = pkgs.rustPlatform.buildRustPackage {
    pname = "pigma";
    version = "0.2.15";

    src = pkgs.fetchFromGitHub {
      owner = "akirco";
      repo = "pigma";
      rev = "v0.2.15";
      # FOD 输出路径由该 hash 决定: 喂旧 hash 时 store/缓存里同名 outPath 直接
      # 替换旧源码 (不重新拉取), 构建"看似正常"实为旧文件 —— 换 rev 必须同步
      # 换 hash (fakeHash 试错拿 got: 值); 2026-09-25 切 fork 实测踩坑
      hash = "sha256-/jlT6OKm3KCXY3DxQ30CXxClt5qMoc89Ce7hB4SNwks=";
      # crates/y7dl 是 git submodule (sonar 的路径依赖), GitHub tarball
      # 不含 submodule, 缺它则 cargo 解析 sonar 依赖时报 ENOENT
      # (上游指向 akirco/y7dl, v0.2.15 已含同款 TOML 修复)
      fetchSubmodules = true;
    };

    # 强制 lld + x86-64-v3 的上游配置, Nix 沙箱无 lld 链接失败 (见文件头)
    postPatch = ''
      rm .cargo/config.toml
    '';

    cargoHash = "sha256-v/pbPt9FTYctsNSw1AptLhZxanNmJF0AdajaPiCLrv4=";

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
