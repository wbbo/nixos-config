# pigma —— 终端 TUI 网易云音乐客户端 (Rust/Ratatui, 非 Electron)
# nixpkgs 未收编, 以 rustPlatform.buildRustPackage 从上游 tag 构建:
# - 音频 rodio → cpal → 动态链接 libasound.so.2: buildInputs 补 alsa-lib
#   (pkg-config 供 alsa-sys 探测), Nix rpath 机制保证运行时解析 ——
#   这也是不能裸 `cargo install` 的原因 (NixOS 无 FHS, 产物缺 libasound);
# - 播放输出走 ALSA default 设备, 实际由 pipewire-alsa 接管;
# - TLS 为 rustls (ring), 无 OpenSSL 依赖;
# - 字体要求 Nerd Font, 默认终端字体 Maple Mono NF CN 已满足。
#
# 注: 曾内置 pigma-mpris 桥 (轮询 status --json 发布 MPRIS 供 Noctalia
# 媒体组件识别), 已移除恢复默认 —— pigma 无 MPRIS, Noctalia 媒体卡片不
# 显示 pigma, 播放控制走 pigma 自带 TUI/CLI IPC。
{ pkgs, lib, ... }:
let
  # 上游子模块 (crates/ncm-api, crates/y7dl) 的 Cargo.toml 把依赖写成跨行
  # inline table (reqwest = { 换行 version = ... }) —— TOML 1.0 只允许单行
  # inline table, 新 cargo (toml_edit 解析器) 严格拒绝; 旧 cargo 宽容所以
  # 上游自己编得过。构建前折成单行: 连同其中的多行数组一并摊平, inline
  # table 收口 "}" 前的尾逗号 (非法) 顺手去掉, 数组尾逗号合法则保留。
  fixCargoToml = pkgs.writers.writePython3 "fix-cargo-toml" { } ''
    import pathlib
    import re

    OPEN = re.compile(r"^(\s*[\w.-]+\s*=\s*)\{$")


    def join_inline_tables(path):
        lines = path.read_text().splitlines()
        out = []
        buf = None
        depth = 0
        for line in lines:
            if buf is None:
                m = OPEN.match(line)
                if m:
                    buf = m.group(1) + "{ "
                    depth = 1
                else:
                    out.append(line)
                continue
            depth += line.count("{") - line.count("}")
            s = line.strip()
            if depth <= 0:
                s = s[:-1].rstrip()
                if s.endswith(","):
                    s = s[:-1]
                out.append(buf + s + " }")
                buf = None
            else:
                buf += s + " "
        path.write_text("\n".join(out) + "\n")


    targets = [pathlib.Path("Cargo.toml")]
    targets += list(pathlib.Path("crates").glob("*/Cargo.toml"))
    for t in targets:
        if t.exists():
            join_inline_tables(t)
  '';

  pigma = pkgs.rustPlatform.buildRustPackage {
    pname = "pigma";
    # 上游 v0.2.14 (2026-09 前) 之后未再发 tag, 此为 main HEAD:
    # 仅 dependabot bump ratatui-image 11.0.6 → 11.0.8 (2026-09-13 合并)。
    # 若上游出新 tag, 把 rev 换回 "v<version>" 并还原 version 即可。
    version = "0.2.14-unstable-2026-09-13";

    src = pkgs.fetchFromGitHub {
      owner = "akirco";
      repo = "pigma";
      rev = "21c380de3f9b3c45c5d16be6aa2e8f2c9ab9c32a";
      # FOD 输出路径由该 hash 决定: 改 fetchSubmodules 后 hash 不变则
      # 直接复用旧产物 (无 submodule), 必须同步换新 hash 才会重新拉取
      hash = "sha256-E6vAuKOCsUInbw6OKX5IvzZzu1cdGWAoF7IGi8PAkfc=";
      # crates/y7dl 是 git submodule (sonar 的路径依赖), GitHub tarball
      # 不含 submodule, 缺它则 cargo 解析 sonar 依赖时报 ENOENT
      fetchSubmodules = true;
    };

    cargoHash = "sha256-X4sRm1MJck58/OIGvQjAKmEI1ZqsAms9RK8DMS9+Yls=";

    # 上游 .cargo/config.toml 强制 -fuse-ld=lld (发布流水线自带 lld),
    # 构建沙箱无 lld → 最终链接 collect2 报 "cannot find 'ld'"。
    # 删掉交回默认链接器; 顺带去掉 target-cpu=x86-64-v3 的 CPU 门槛
    # (保留会排除老机器, 不符合分发模板语义, 性能差异可忽略)。
    postPatch = ''
      rm -f .cargo/config.toml
      ${fixCargoToml}
      # 上游 debug 日志对响应体做 &result[..len().min(N)] 截断, 不查 UTF-8
      # 字符边界 —— 字节 N 恰落在中文多字节字符中间即 panic (实测: 切到
      # "收藏的歌单"闪退, playlist.rs:207)。get(..N) 切不动 (越界/跨界)
      # 时退化为记全文: debug 级日志无所谓长度, 语义兼容原意。
      substituteInPlace crates/ncm-api/src/client/playlist.rs \
        crates/ncm-api/src/client/home.rs \
        --replace '&result[..result.len().min(500)]' \
                 'result.get(..500).unwrap_or(&result)' \
        --replace '&result[..result.len().min(2000)]' \
                 'result.get(..2000).unwrap_or(&result)'
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
  };
in
{
  home.packages = [ pigma ];
}
