# 企业微信 (WeCom) —— Bottles/Wine 运行 + 显示修复 + prefix 适配
#
# 三块内容:
#   1. 适配服务 (wework-adapt): 固化 doc/wework.md 记录的成功配置 ——
#      caffe runner / XWeb 硬件加速禁用 / 字体替换。幂等自检 + 补齐。
#   2. ARGB 子窗修复守护 (wework-fix): 见下方注释, 上游修复后可退役。
#   3. 启动器 (wework-launch) + 桌面项。
#
# 完整适配记录与踩坑清单: doc/wework.md
{ config
, pkgs
, ...
}:
let
  # ARGB 守护的扫描逻辑 (见文件末尾服务定义处的根因说明)
  fixPy = pkgs.writeText "wework-fix.py" ''
  import ctypes
  import os
  import select
  import sys
  import time

  # 直接调 libX11 (不经 xdotool/xwininfo 子进程): 事件驱动、毫秒级响应。
  # pkgs.libx11 (非 pkgs.xorg.libX11 —— 后者是废弃别名, 会触发求值警告;
  # 两者指向同一个包, 产物路径不变)
  LIBX11 = "${pkgs.libx11}/lib/libX11.so.6"

  SWEEP_INTERVAL = 5.0   # 秒; 兜底全量清扫周期 (事件之外的保险)
  CONNECT_RETRY = 5.0    # 秒; X 未就绪时的重连间隔

  SubstructureNotifyMask = 1 << 19
  MapNotify = 19
  UnmapNotify = 18
  CreateNotify = 16
  ReparentNotify = 21
  ConfigureNotify = 22

  IsViewable = 2
  InputOutput = 1


  class XWindowAttributes(ctypes.Structure):
      _fields_ = [
          ("x", ctypes.c_int), ("y", ctypes.c_int),
          ("width", ctypes.c_int), ("height", ctypes.c_int),
          ("border_width", ctypes.c_int), ("depth", ctypes.c_int),
          ("visual", ctypes.c_void_p), ("root", ctypes.c_ulong),
          ("klass", ctypes.c_int), ("bit_gravity", ctypes.c_int),
          ("win_gravity", ctypes.c_int), ("backing_store", ctypes.c_int),
          ("backing_planes", ctypes.c_ulong), ("backing_pixel", ctypes.c_ulong),
          ("save_under", ctypes.c_int), ("colormap", ctypes.c_ulong),
          ("map_installed", ctypes.c_int), ("map_state", ctypes.c_int),
          ("all_event_masks", ctypes.c_long), ("your_event_mask", ctypes.c_long),
          ("do_not_propagate_mask", ctypes.c_long),
          ("override_redirect", ctypes.c_int), ("screen", ctypes.c_void_p),
      ]


  class XClassHint(ctypes.Structure):
      _fields_ = [("res_name", ctypes.c_void_p), ("res_class", ctypes.c_void_p)]


  class XMapEvent(ctypes.Structure):
      """XEvent 联合体中我们只读 MapNotify/UnmapNotify 的 window 字段。"""
      _fields_ = [
          ("type", ctypes.c_int), ("serial", ctypes.c_ulong),
          ("send_event", ctypes.c_int), ("display", ctypes.c_void_p),
          ("event", ctypes.c_ulong), ("window", ctypes.c_ulong),
          ("override_redirect", ctypes.c_int),
      ]


  x = ctypes.CDLL(LIBX11)
  x.XOpenDisplay.restype = ctypes.c_void_p
  x.XOpenDisplay.argtypes = [ctypes.c_char_p]
  x.XDefaultRootWindow.restype = ctypes.c_ulong
  x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
  x.XConnectionNumber.restype = ctypes.c_int
  x.XConnectionNumber.argtypes = [ctypes.c_void_p]
  x.XSelectInput.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_long]
  x.XPending.restype = ctypes.c_int
  x.XPending.argtypes = [ctypes.c_void_p]
  x.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
  x.XGetWindowAttributes.restype = ctypes.c_int
  x.XGetWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                                     ctypes.POINTER(XWindowAttributes)]
  x.XFetchName.restype = ctypes.c_int
  x.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                           ctypes.POINTER(ctypes.c_void_p)]
  x.XGetClassHint.restype = ctypes.c_int
  x.XGetClassHint.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                              ctypes.POINTER(XClassHint)]
  x.XQueryTree.restype = ctypes.c_int
  x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                           ctypes.POINTER(ctypes.c_ulong),
                           ctypes.POINTER(ctypes.c_ulong),
                           ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
                           ctypes.POINTER(ctypes.c_uint)]
  x.XUnmapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
  x.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
  x.XFree.argtypes = [ctypes.c_void_p]

  IOERR = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)


  def _io_error(_dpy):
      # X 连接断开 (satellite / X server 重启) —— Xlib 无法从 IO 错误中恢复,
      # 干净退出交给 systemd 重启 (Restart=on-failure), 重启后的首轮全量清扫兜底。
      print("X 连接断开, 退出等待 systemd 重启", flush=True)
      os._exit(1)


  x.XSetIOErrorHandler.restype = ctypes.c_void_p
  x.XSetIOErrorHandler.argtypes = [IOERR]
  _ioerr_cb = IOERR(_io_error)   # 必须持有引用, 否则回调可能被 GC
  x.XSetIOErrorHandler(_ioerr_cb)

  EVBUF = ctypes.create_string_buffer(256)   # XEvent 联合体足够大


  def wxwork_running():
      """进程门禁: 按 comm 匹配, 不看 cmdline。

      历史坑: 原实现扫 /proc/*/cmdline 找 "WXWork.exe", 会被命令行里含该字面量
      的**残留 wrapper** 骗到 —— `timeout … bottles-cli run … WXWork.exe`、
      `bwrap … bottles-cli run …`、`crashpad_handler.exe`(路径含 WXWork) 都命中,
      即使企业微信已退出也让门禁判"运行中", 导致 wework-adapt 一直跳过。
      comm 是内核给的进程名, wrapper 的 comm 是 bash/timeout/bwrap, 不会误判。
      """
      try:
          for pid in os.listdir("/proc"):
              if not pid.isdigit():
                  continue
              try:
                  with open(f"/proc/{pid}/comm", "rb") as f:
                      if f.read().strip().startswith(b"WXWork"):
                          return True
              except OSError:
                  pass
      except OSError:
          pass
      return False


  def classify(dpy, wid):
      """返回 ("ARGB"|"tray"|None)。判据与原轮询版一致, 只换成 Xlib 直读。"""
      attrs = XWindowAttributes()
      if not x.XGetWindowAttributes(dpy, wid, ctypes.byref(attrs)):
          return None
      if attrs.klass != InputOutput or attrs.map_state != IsViewable:
          return None

      hint = XClassHint()
      cls = ""
      if x.XGetClassHint(dpy, wid, ctypes.byref(hint)):
          if hint.res_name:
              cls += ctypes.string_at(hint.res_name).decode("utf-8", "replace")
              x.XFree(hint.res_name)
          if hint.res_class:
              cls += " " + ctypes.string_at(hint.res_class).decode("utf-8", "replace")
              x.XFree(hint.res_class)
      low = cls.lower()

      if "explorer" in low:
          # wine 托盘窗 (explorer.exe 的白色图标横条): >4x4 才动 (保护 1x1 消息窗)
          if attrs.width > 4 and attrs.height > 4:
              return "tray"

      # ── 已退役: wxwork 的 "ARGB 外框窗" unmap (2026-09-18) ──────────────
      # 原本这里会把「无名 + Depth 32 + >10x10」的 wxwork 窗 unmap 掉, 因为
      # 那些透明外框窗会被渲染成不透明黑、盖住应用。
      #
      # 真因已定位并绕过: 是 **niri 在 dmabuf 路径上丢 alpha** (见 doc/wework.md
      # §8.3), 由 niri 模块的 `-glamor none` wrapper 解决 (§8.9)。alpha 正常后
      # 这些窗**本来就该显示** (它们是窗口外框/阴影, 正常渲染才是设计意图), 继续
      # unmap 反而有害:
      #   1. 实测和应用拉锯 —— 应用反复重映射, 守护 2 分钟 unmap 39 次;
      #   2. **会打断应用的输入** (unmap 掉应用命中测试依赖的窗口 → 鼠标点击无反应,
      #      与 §2.4 "unmap Default IME 导致点击失效" 同源)。
      # 若哪天 wrapper 丢失、黑窗复现, 把下面这段恢复即可 (判据: 空串标题也算无名 ——
      # XFetchName 返回 1 但内容为 "" 的窗必须当作无名, 早期只看指针非 NULL 会漏掉)。
      return None


  def fix(dpy, wid, tag):
      x.XUnmapWindow(dpy, wid)
      x.XSync(dpy, 0)
      print(f"unmap {tag} {hex(wid)} ok", flush=True)


  def handle(dpy, wid):
      tag = classify(dpy, wid)
      if tag:
          fix(dpy, wid, tag)


  def sweep(dpy, root):
      """全量清扫 root 直接子窗。

      只扫 root 的子窗是有依据的: satellite 也只接管 root 直接子窗
      (src/xstate/mod.rs:362, parent != root 直接 destroy), 非 root 子窗不可能
      有自己的 Wayland surface, 也就不会显示出来。
      """
      rt = ctypes.c_ulong(); par = ctypes.c_ulong()
      kids = ctypes.POINTER(ctypes.c_ulong)()
      n = ctypes.c_uint()
      if not x.XQueryTree(dpy, root, ctypes.byref(rt), ctypes.byref(par),
                          ctypes.byref(kids), ctypes.byref(n)):
          return
      try:
          for i in range(n.value):
              handle(dpy, kids[i])
      finally:
          if kids:
              x.XFree(kids)


  def connect():
      dpy = x.XOpenDisplay(None)
      if not dpy:
          return None
      root = x.XDefaultRootWindow(dpy)
      x.XSelectInput(dpy, root, SubstructureNotifyMask)
      x.XSync(dpy, 0)
      return dpy, root


  def main():
      dpy = None
      while dpy is None:
          try:
              dpy = connect()
          except Exception as exc:
              print(f"X 连接异常: {exc!r}", flush=True)
              dpy = None
          if dpy is None:
              print(f"连不上 X, {CONNECT_RETRY:g}s 后重试", flush=True)
              time.sleep(CONNECT_RETRY)
      dpy, root = dpy
      print("已连上 X, 监听 root 的 SubstructureNotify", flush=True)

      last_sweep = 0.0
      fd = x.XConnectionNumber(dpy)
      while True:
          # 事件优先: 毫秒级响应新映射的窗口
          try:
              while x.XPending(dpy):
                  x.XNextEvent(dpy, EVBUF)
                  ev = ctypes.cast(EVBUF, ctypes.POINTER(XMapEvent)).contents
                  # 只处理"窗口变为可见"的事件; Unmap/Destroy/Configure 不需要动作
                  if ev.type == MapNotify:
                      handle(dpy, ev.window)
          except Exception as exc:
              print(f"事件处理异常: {exc!r}", flush=True)

          now = time.monotonic()
          if now - last_sweep >= SWEEP_INTERVAL:
              last_sweep = now
              if wxwork_running():
                  try:
                      sweep(dpy, root)
                  except Exception as exc:
                      print(f"清扫异常: {exc!r}", flush=True)

          try:
              select.select([fd], [], [], 1.0)
          except (OSError, ValueError) as exc:
              print(f"select 异常: {exc!r}", flush=True)
              time.sleep(1.0)


  if __name__ == "__main__":
      main()
  '';
  weworkFixScript = pkgs.writeShellApplication {
    name = "wework-fix-subwindow";
    # 直连 libX11 (ctypes), 不再需要 xwininfo/xdotool 子进程
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${fixPy}
    '';
  };

  weworkLaunch = pkgs.writeShellApplication {
    name = "wework-launch";
    runtimeInputs = [ pkgs.flatpak ];
    text = ''
      exec flatpak run --command=bottles-cli com.usebottles.bottles run \
        -b Work -e 'C:\Program Files (x86)\WXWork\WXWork.exe'
    '';
  };

  # 适配脚本 (适配项: runner / XWeb 硬件加速策略 / 字体替换)。
  # bashOptions 不设 —— 默认 [ "errexit" "nounset" "pipefail" ] 已等价脚本内
  # 的 set -euo pipefail。bashOptions 每项生成一行 `set -o <name>`, 只认长名;
  # 曾误写短名 [ "e" "u" "o" ], 生成 `set -o e` 非法, 三行 set 全部报错,
  # 严格模式静默失效 (脚本照跑但失去错误保护)。
  adaptScript = pkgs.writeShellApplication {
    name = "wework-adapt";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnutar
      pkgs.gzip
      pkgs.xz
      pkgs.iconv
      pkgs.procps
      pkgs.flatpak
    ];
    text = ''
      exec ${pkgs.bash}/bin/bash ${./wework/adapt.sh}
    '';
  };
in
{
  # ── 适配服务 ────────────────────────────────────────────────────────────
  # 幂等: 三项配置逐项自检 prefix 实际状态, 已就绪即跳过。定时重试处理两类
  # 需要等待的情形 —— 激活时企业微信正在运行 (改 runner 会打断会话), 以及
  # Bottles/bottle 尚未补齐 (flatpak-apps 服务负责装应用, bottle 本体在 persist)。
  systemd.user.services.wework-adapt = {
    Unit = {
      Description = "WeCom (Bottles) prefix adaptation (runner / XWeb policy / font substitution)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      # runner 下载最坏 600s, 其余步骤秒级; 留足余量
      TimeoutStartSec = "15min";
      ExecStart = "${adaptScript}/bin/wework-adapt";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.timers.wework-adapt = {
    Unit.Description = "Periodically ensure WeCom prefix adaptation (retry until converged)";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      AccuracySec = "1min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # ── 托盘窗清理守护 (原 "ARGB 黑窗守护", 2026-09-18 已瘦身) ───────────────
  #
  # 历史: 本守护原本的核心职责是 unmap 企业微信创建的**透明 Depth-32 外框窗**
  # (它们被渲染成不透明黑盖住应用)。真因已于 2026-09-18 定位:
  # **niri 在 dmabuf 路径上丢 ARGB buffer 的 alpha** (doc/wework.md §8.3), 由
  # niri 模块的 `-glamor none` wrapper 绕过 (§8.9)。alpha 正常后那些外框窗
  # 本来就是应用的正常 UI, 不需要 (也不应该) 摘掉 —— 摘了会和应用拉锯,
  # 更要命的是**会打断应用的输入** (鼠标点击无反应; 与 §2.4 unmap Default IME
  # 导致点击失效同源)。故 ARGB 判据已退役, 判据函数里留有恢复用的注释。
  #
  # 现仅保留: explorer.exe 的 wine 托盘横条 unmap (独立问题)。
  #
  # 工作方式: **事件驱动** —— 在 root 上选 SubstructureNotify, 收到 MapNotify
  # 即判窗并 unmap, 实测延迟 ~1ms; 另有每 SWEEP_INTERVAL 的全量清扫兜底
  # (兼作重启后的首轮清理)。全量清扫只扫 root 子窗 —— 非 root 子窗不可能有
  # 自己的 surface, 也就不会显示出来。
  # X 连接断开 (satellite/X server 重启) 时 Xlib 无法恢复 → 进程干净退出,
  # 由 systemd 重启后重新清扫 (RestartSec 已调小)。
  # 进程门禁按 **comm** 匹配 (不看 cmdline): 原实现扫 /proc/*/cmdline 找
  # "WXWork.exe", 会被命令行含该字面量的残留 wrapper (timeout/bwrap/
  # crashpad_handler) 骗到, 导致 wework-adapt 一直跳过 (09-17 实测卡 6 轮)。
  # 注意: 不可杀 explorer.exe 进程 —— 它是 wine 会话的桌面进程, 杀掉会连带
  # 终止整个 wine 会话 (企业微信一起退出)。
  systemd.user.services.wework-fix = {
    Unit = {
      Description = "WeCom (Bottles) ARGB window auto-fix";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Environment = [ "DISPLAY=:0" ];
      ExecStart = "${weworkFixScript}/bin/wework-fix-subwindow";
      Restart = "on-failure";
      # X 重启后要尽快恢复监听 (守护最该工作的场景)
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # 启动器 wrapper: desktop 的 Exec 字段里写 Windows 路径的转义极绕
  # (desktop-file-validate 实测报 "contains a quote which is not closed"),
  # 用脚本封装, Exec 只写脚本名。flatpak 走 runtimeInputs 保证 PATH 可达。
  home.packages = [ weworkLaunch ];

  # 桌面项: 让启动器 (Mod+Space) 能搜索并启动企业微信。
  # 图标用 Bottles 已从 exe 提取的 WXWork.png。
  # 单实例: 已在运行时再次启动会静默退出 (企业微信自身行为, 无害)。
  xdg.dataFile."applications/wework.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=企业微信
    Name[en_US]=WeCom
    GenericName=企业通讯
    Comment=企业微信 (Bottles/Wine)
    Exec=wework-launch
    Icon=${config.home.homeDirectory}/.var/app/com.usebottles.bottles/data/bottles/bottles/Work/icons/WXWork.png
    Terminal=false
    Categories=Network;InstantMessaging;
    Keywords=wecom;wework;wxwork;企业微信;微信;
    StartupNotify=false
  '';
}
