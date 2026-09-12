# 企业微信 (Bottles) ARGB 子窗修复守护 (轮询版)
# 根因: 企业微信的 CEF/XWeb 把 GPU 合成内容画在一个 32 位 ARGB 子窗口 (Depth 32,
# 无名), 在 NVIDIA + xwayland-satellite 下该子窗内容不填充 (未初始化 GPU buffer),
# 盖住下层正常 GDI 绘制的 UI → 整窗黑/黑块。satellite 缓存首帧黑帧不重抓, 运行中
# 新建窗口 (双击菜单/弹框) 因此持续黑屏。上游 issue #502。
#
# 工作方式: 2 秒周期扫描窗口树, unmap 故障 ARGB 窗与 explorer 托盘横条。
# 为什么是轮询而非 X 事件: root 的 SubstructureNotify 只上报直接子窗, 故障 ARGB
# 窗是孙窗 (事件收不到, 事件驱动曾形同虚设); 且 Xlib 连接在 satellite 重启
# (守护最该工作的场景) 时抛异常杀死进程。轮询用外部命令 + 超时, X 抖动只损失
# 一轮。进程门禁: 企业微信未运行时整个会话零扫描开销。
# 注意: 不可杀 explorer.exe 进程 —— 它是 wine 会话的桌面进程, 杀掉会连带终止
# 整个 wine 会话 (企业微信一起退出)。
{ config, pkgs, ... }: let
  fixPy = pkgs.writeText "wework-fix.py" ''
    import os
    import re
    import subprocess
    import time

    SCAN_INTERVAL = 1  # 秒; 原 2 秒在菜单/弹框场景可感知 (最坏 2 秒才 unmap),
                       # 减半以平衡延迟与扫描开销 (进程门禁保证企业微信未运行
                       # 时仍为零开销; 单轮 = 1 次全树 + 每候选窗 1 次 xwininfo)

    def sh(*args):
        # timeout 兜底: X 卡死时不阻塞; errors=replace: 非 UTF-8 窗标题
        # (Java/Motif/GBK) 不抛异常
        try:
            return subprocess.run(
                args, capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=5,
            ).stdout
        except (subprocess.TimeoutExpired, OSError):
            return ""

    def unmap(wid, tag):
        try:
            r = subprocess.run(["xdotool", "windowunmap", wid],
                               capture_output=True, timeout=5)
            status = "ok" if r.returncode == 0 else f"rc={r.returncode}"
        except (subprocess.TimeoutExpired, OSError) as exc:
            status = f"fail {exc!r}"
        print(f"unmap {tag} {wid} {status}", flush=True)

    def wxwork_running():
        # 进程门禁 (走 procfs, 无子进程开销): 企业微信未运行时跳过扫描
        try:
            for pid in os.listdir("/proc"):
                if not pid.isdigit():
                    continue
                try:
                    with open(f"/proc/{pid}/cmdline", "rb") as f:
                        if b"WXWork.exe" in f.read():
                            return True
                except OSError:
                    pass
        except OSError:
            pass
        return False

    def fix_wxwork_argb(tree):
        # 故障合成窗判据: 无名 + 可见 + Depth 32 + 尺寸 > 10x10。
        # 正常 UI 子窗均为 Depth 24 不受影响; 排除 1x1 消息窗 (Default IME 等
        # 被 unmap 曾导致输入失效)。
        for line in tree.splitlines():
            if "has no name" not in line or "wxwork.exe" not in line:
                continue
            m = re.match(r"\s*(0x[0-9a-f]+)", line)
            if not m:
                continue
            wid = m.group(1)
            stats = sh("xwininfo", "-id", wid, "-stats")
            ms = re.search(r"Map State:\s*(\w+)", stats)
            w = re.search(r"Width:\s*(\d+)", stats)
            h = re.search(r"Height:\s*(\d+)", stats)
            d = re.search(r"Depth:\s*(\d+)", stats)
            if not (ms and w and h and d):
                continue
            if ms.group(1) != "IsViewable" or d.group(1) != "32":
                continue
            if int(w.group(1)) > 10 and int(h.group(1)) > 10:
                unmap(wid, "ARGB")

    def fix_explorer_tray(tree):
        # wine 托盘窗 (explorer.exe, 白色图标横条): unmap 隐藏。
        # 几何从行尾锚定 (相对+绝对坐标对), 避免窗口标题含 "NxM+" 时误匹配;
        # 尺寸过滤 > 4x4 保护 1x1 消息窗 (被 unmap 曾导致输入失效)。
        for line in tree.splitlines():
            if "explorer.exe" not in line:
                continue
            m = re.match(
                r"\s*(0x[0-9a-f]+)\s.*?(\d+)x(\d+)\+\d+\+\d+\s+\+\d+\+\d+\s*$",
                line,
            )
            if not m:
                continue
            wid, w, h = m.group(1), int(m.group(2)), int(m.group(3))
            if w <= 4 or h <= 4:
                continue
            stats = sh("xwininfo", "-id", wid, "-stats")
            ms = re.search(r"Map State:\s*(\w+)", stats)
            if ms and ms.group(1) == "IsViewable":
                unmap(wid, "tray")

    while True:
        try:
            if wxwork_running():
                tree = sh("xwininfo", "-root", "-tree")
                if tree:
                    fix_wxwork_argb(tree)
                    fix_explorer_tray(tree)
        except Exception as exc:  # 单轮失败不杀进程, 记录后继续
            print(f"scan error: {exc!r}", flush=True)
        time.sleep(SCAN_INTERVAL)
  '';
  weworkFixScript = pkgs.writeShellApplication {
    name = "wework-fix-subwindow";
    runtimeInputs = [
      pkgs.python3
      pkgs.xorg.xwininfo
      pkgs.xdotool
    ];
    text = ''
      exec python3 ${fixPy}
    '';
  };

  # 启动器 wrapper: desktop 的 Exec 字段里写 Windows 路径的转义极绕
  # (desktop-file-validate 实测报 "contains a quote which is not closed"),
  # 用脚本封装, Exec 只写脚本名。flatpak 走 runtimeInputs 保证 PATH 可达。
  weworkLaunch = pkgs.writeShellApplication {
    name = "wework-launch";
    runtimeInputs = [ pkgs.flatpak ];
    text = ''
      exec flatpak run --command=bottles-cli com.usebottles.bottles run \
        -b 企业微信 -e 'C:\Program Files (x86)\WXWork\WXWork.exe'
    '';
  };
in {
  home.packages = [ weworkLaunch ];
  systemd.user.services.wework-fix = {
    Unit = {
      Description = "WeCom (Bottles) ARGB subwindow auto-fix";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Environment = [ "DISPLAY=:0" ];
      ExecStart = "${weworkFixScript}/bin/wework-fix-subwindow";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # 桌面项: 让启动器 (Mod+Space) 能搜索并启动企业微信。
  # 此前没有 .desktop, 只能开 Bottles GUI 手动点。Exec 走 wework-launch
  # wrapper (desktop 的 Exec 转义规则写 Windows 路径会失败, 见上方注释)。
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
    Icon=${config.home.homeDirectory}/.var/app/com.usebottles.bottles/data/bottles/bottles/企业微信/icons/WXWork.png
    Terminal=false
    Categories=Network;InstantMessaging;
    Keywords=wecom;wework;wxwork;企业微信;微信;
    StartupNotify=false
  '';
}
