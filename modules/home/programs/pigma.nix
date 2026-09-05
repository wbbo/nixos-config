# pigma —— 终端 TUI 网易云音乐客户端 (Rust/Ratatui, 非 Electron)
# nixpkgs 未收编, 以 rustPlatform.buildRustPackage 从上游 tag 构建:
# - 音频 rodio → cpal → 动态链接 libasound.so.2: buildInputs 补 alsa-lib
#   (pkg-config 供 alsa-sys 探测), Nix rpath 机制保证运行时解析 ——
#   这也是不能裸 `cargo install` 的原因 (NixOS 无 FHS, 产物缺 libasound);
# - 播放输出走 ALSA default 设备, 实际由 pipewire-alsa 接管;
# - TLS 为 rustls (ring), 无 OpenSSL 依赖;
# - 字体要求 Nerd Font, 默认终端字体 Maple Mono NF CN 已满足。
{ pkgs, lib, ... }:
{
  home.packages = [
    (pkgs.rustPlatform.buildRustPackage rec {
      pname = "pigma";
      version = "0.2.13";

      src = pkgs.fetchFromGitHub {
        owner = "akirco";
        repo = "pigma";
        rev = "v${version}";
        # FOD 输出路径由该 hash 决定: 改 fetchSubmodules 后 hash 不变则
        # 直接复用旧产物 (无 submodule), 必须同步换新 hash 才会重新拉取
        hash = "sha256-Vx26PkLNt56zuhAFguDpi+nA8vPlFInwKREYS3pNpOA=";
        # crates/y7dl 是 git submodule (sonar 的路径依赖), GitHub tarball
        # 不含 submodule, 缺它则 cargo 解析 sonar 依赖时报 ENOENT
        fetchSubmodules = true;
      };

      cargoHash = "sha256-iveDoONE4mn1sgEmThdP0d+NiYlvHA7xPtM27JmDnCE=";

      # 上游 .cargo/config.toml 强制 -fuse-ld=lld (发布流水线自带 lld),
      # 构建沙箱无 lld → 最终链接 collect2 报 "cannot find 'ld'"。
      # 删掉交回默认链接器; 顺带去掉 target-cpu=x86-64-v3 的 CPU 门槛
      # (保留会排除老机器, 不符合分发模板语义, 性能差异可忽略)。
      postPatch = ''
        rm -f .cargo/config.toml
      '';

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
    })
  ];
}
