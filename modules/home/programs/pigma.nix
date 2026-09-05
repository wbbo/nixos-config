# pigma —— 终端 TUI 网易云音乐客户端 (Rust/Ratatui, 非 Electron)
# nixpkgs 未收编, 以 rustPlatform.buildRustPackage 从上游 tag 构建:
# - 音频 rodio → cpal → 动态链接 libasound.so.2: buildInputs 补 alsa-lib
#   (pkg-config 供 alsa-sys 探测), Nix rpath 机制保证运行时解析 ——
#   这也是不能裸 `cargo install` 的原因 (NixOS 无 FHS, 产物缺 libasound);
# - 播放输出走 ALSA default 设备, 实际由 pipewire-alsa 接管;
# - TLS 为 rustls (ring), 无 OpenSSL 依赖;
# - 字体要求 Nerd Font, 默认终端字体 Maple Mono NF CN 已满足。
#
# ── Noctalia 媒体联动 (pigma-mpris 桥) ──────────────────────────────────
# pigma 无 MPRIS, 对外只有 CLI IPC (status --json / msg); Noctalia 媒体
# 组件只认 MPRIS (org.mpris.MediaPlayer2)。桥以 systemd 用户服务常驻:
# 轮询 pigma 状态发布标准 MPRIS 属性 (Noctalia 零配置识别), MPRIS 调用
# (play/pause/next/previous/volume) 翻译回 `pigma msg`。pigma 不支持
# seek → CanSeek=False; daemon 离线时释放总线名 → Noctalia 自动隐藏卡片。
{ pkgs, lib, ... }:
let
  pigma = pkgs.rustPlatform.buildRustPackage rec {
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
  };

  # 桥脚本。python 代码必须顶格 —— nix '' 字符串逐字保留缩进,
  # python 对首层缩进敏感; ${pigma} 为 nix 插值 (store 绝对路径)。
  pigmaMprisPy = pkgs.writeText "pigma-mpris.py" ''
import asyncio
import json
import subprocess

from dbus_next import PropertyAccess, Variant
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method, dbus_property

PIGMA = "${pigma}/bin/pigma"
BUS_NAME = "org.mpris.MediaPlayer2.pigma"
OBJ_PATH = "/org/mpris/MediaPlayer2"
POLL_SEC = 1


def run_pigma(args):
    # pigma IPC 是 unix socket CLI, 单次调用毫秒级; timeout 兜底 daemon 卡死
    try:
        return subprocess.run([PIGMA] + args, capture_output=True, text=True, timeout=3)
    except Exception:
        return None


def fetch_status():
    r = run_pigma(["status", "--json"])
    if not r or r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


class Root(ServiceInterface):
    # org.mpris.MediaPlayer2 (根接口): Raise/Quit 无对应能力, 声明不可用
    def __init__(self):
        super().__init__("org.mpris.MediaPlayer2")

    @method()
    def Raise(self):
        pass

    @method()
    def Quit(self):
        pass

    @dbus_property(PropertyAccess.READ)
    def CanQuit(self) -> "b":
        return False

    @dbus_property(PropertyAccess.READ)
    def CanRaise(self) -> "b":
        return False

    @dbus_property(PropertyAccess.READ)
    def CanSetFullscreen(self) -> "b":
        return False

    @dbus_property(PropertyAccess.READ)
    def HasTrackList(self) -> "b":
        return False

    @dbus_property(PropertyAccess.READ)
    def Identity(self) -> "s":
        return "pigma"

    @dbus_property(PropertyAccess.READ)
    def DesktopEntry(self) -> "s":
        return "pigma"

    @dbus_property(PropertyAccess.READ)
    def SupportedUriSchemes(self) -> "as":
        return []

    @dbus_property(PropertyAccess.READ)
    def SupportedMimeTypes(self) -> "as":
        return []


class Player(ServiceInterface):
    # org.mpris.MediaPlayer2.Player: 属性值来自最近一次轮询快照 (self.st),
    # 写操作翻译为 pigma msg。pigma 无 seek → CanSeek=False, 进度条只读。
    def __init__(self):
        super().__init__("org.mpris.MediaPlayer2.Player")
        self.st = None

    async def cmd(self, *args):
        await asyncio.to_thread(run_pigma, list(args))

    @method()
    async def Play(self):
        await self.cmd("msg", "play")

    @method()
    async def Pause(self):
        await self.cmd("msg", "pause")

    @method()
    async def PlayPause(self):
        await self.cmd("msg", "toggle_play")

    @method()
    async def Next(self):
        await self.cmd("msg", "next")

    @method()
    async def Previous(self):
        await self.cmd("msg", "previous")

    @method()
    async def Stop(self):
        await self.cmd("msg", "pause")

    def playback_status(self) -> str:
        st = self.st or {}
        if st.get("playing"):
            return "Playing"
        if st.get("paused"):
            return "Paused"
        return "Stopped"

    @dbus_property(PropertyAccess.READ)
    def PlaybackStatus(self) -> "s":
        return self.playback_status()

    @dbus_property(PropertyAccess.READ)
    def LoopStatus(self) -> "s":
        # pigma mode 无法定向设定 (只能循环切换), 只读反映近似状态
        mode = (self.st or {}).get("mode")
        if mode == "repeat_one":
            return "Track"
        if mode == "repeat_all":
            return "Playlist"
        return "None"

    @dbus_property(PropertyAccess.READ)
    def Shuffle(self) -> "b":
        return (self.st or {}).get("mode") == "shuffle"

    # 值计算抽成普通方法: dbus_property 装饰后实例属性即属性值,
    # emit_properties_changed 需调用底层 getter 取最新值
    def metadata(self) -> dict:
        st = self.st or {}
        return {
            "mpris:trackid": Variant("o", "/org/pigma/Track/" + str(st.get("id") or 0)),
            "xesam:title": Variant("s", str(st.get("name") or "")),
            "xesam:artist": Variant("as", [str(st.get("artist") or "")]),
            "xesam:album": Variant("s", str(st.get("album") or "")),
            "mpris:length": Variant("x", int(st.get("duration_ms") or 0) * 1000),
        }

    @dbus_property(PropertyAccess.READ)
    def Metadata(self) -> "a{sv}":
        return self.metadata()

    def volume(self) -> float:
        v = (self.st or {}).get("volume")
        return float(v) if v is not None else 1.0

    @dbus_property(PropertyAccess.READ)
    def Volume(self) -> "d":
        return self.volume()

    @Volume.setter
    def Volume(self, v: "d"):
        # MPRIS 0..1 → pigma volume 绝对值 0-100
        v = max(0, min(100, int(round(float(v) * 100))))
        run_pigma(["msg", "volume", str(v)])

    @dbus_property(PropertyAccess.READ)
    def Position(self) -> "x":
        # 微秒; 不发 PropertiesChanged (MPRIS 规范: Position 由客户端自增)
        return int((self.st or {}).get("position_ms") or 0) * 1000

    @dbus_property(PropertyAccess.READ)
    def Rate(self) -> "d":
        return 1.0

    @dbus_property(PropertyAccess.READ)
    def MinimumRate(self) -> "d":
        return 1.0

    @dbus_property(PropertyAccess.READ)
    def MaximumRate(self) -> "d":
        return 1.0

    @dbus_property(PropertyAccess.READ)
    def CanGoNext(self) -> "b":
        return True

    @dbus_property(PropertyAccess.READ)
    def CanGoPrevious(self) -> "b":
        return True

    @dbus_property(PropertyAccess.READ)
    def CanPlay(self) -> "b":
        return True

    @dbus_property(PropertyAccess.READ)
    def CanPause(self) -> "b":
        return True

    @dbus_property(PropertyAccess.READ)
    def CanSeek(self) -> "b":
        return False

    @dbus_property(PropertyAccess.READ)
    def CanControl(self) -> "b":
        return True


async def poll_loop(bus, root, player):
    registered = False
    last_key = None
    while True:
        st = await asyncio.to_thread(fetch_status)
        online = st is not None
        try:
            # daemon 在线才注册总线名, 离线释放 —— Noctalia 按有无 MPRIS
            # 服务决定显示媒体卡片, 桥本身常驻但不污染空状态
            if online and not registered:
                bus.export(OBJ_PATH, root)
                bus.export(OBJ_PATH, player)
                await bus.request_name(BUS_NAME)
                registered = True
                last_key = None
            elif not online and registered:
                await bus.release_name(BUS_NAME)
                bus.unexport(OBJ_PATH)
                registered = False
            if online:
                player.st = st
                # 曲目/播放态/音量任一变化才发 PropertiesChanged
                k = (st.get("id"), st.get("playing"), st.get("paused"), st.get("volume"))
                if k != last_key:
                    # 同步方法 (内部直接发信号), 不可 await
                    player.emit_properties_changed({
                        "Metadata": player.metadata(),
                        "PlaybackStatus": player.playback_status(),
                        "Volume": player.volume(),
                    })
                    last_key = k
        except Exception:
            # D-Bus 断连等故障冒泡给 systemd 重启, 不空转
            raise
        await asyncio.sleep(POLL_SEC)


async def main():
    bus = await MessageBus().connect()
    await poll_loop(bus, Root(), Player())


asyncio.run(main())
  '';

  pigmaMpris = pkgs.writeShellApplication {
    name = "pigma-mpris";
    runtimeInputs = [
      (pkgs.python3.withPackages (ps: [ ps.dbus-next ]))
    ];
    text = ''
      exec python3 ${pigmaMprisPy} "$@"
    '';
  };
in
{
  home.packages = [
    pigma
    pigmaMpris
  ];

  # Noctalia 媒体联动桥 —— 跟随图形会话启停, 故障自动重启
  systemd.user.services.pigma-mpris = {
    Unit = {
      Description = "MPRIS bridge for pigma (Noctalia media widget)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pigmaMpris}/bin/pigma-mpris";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
