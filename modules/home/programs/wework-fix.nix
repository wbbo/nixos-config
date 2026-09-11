# 企业微信 (Bottles) ARGB 子窗修复守护
# 根因: 企业微信的 CEF/XWeb 把 GPU 合成内容画在一个 32 位 ARGB 子窗口
# (比父窗大), 在 NVIDIA + xwayland-satellite 下该子窗内容不填充 (未初始化
# GPU buffer), 盖住下层正常 GDI 绘制的 UI → 整窗黑/黑块。unmap 子窗后
# 下层 UI 露出即正常。satellite 0.8.2 无开关, 上游 issue #225 跟踪中。
# 本服务轮询: wxwork.exe 存在时, 找 mapped 且尺寸超过顶层窗的无名子窗,
# xdotool windowunmap 之。误伤面小 (仅企业微信的无名大子窗)。
{ pkgs, ... }: let
  weworkFixScript = pkgs.writeShellApplication {
    name = "wework-fix-subwindow";
    # 轮询脚本大量依赖 grep 无匹配继续运行, 关闭 -e/-o pipefail
    bashOptions = [ "u" ];
    runtimeInputs = with pkgs; [ xorg.xwininfo xdotool procps gnugrep gawk ];
    text = ''
      export DISPLAY=''${DISPLAY:-:0}
      while true; do
        if pgrep -f 'WXWork[.]exe' >/dev/null 2>&1; then
          tree=$(xwininfo -root -tree 2>/dev/null)
          # 顶层窗 = wxwork.exe 具名窗中面积最大者 (避开 XWeb 的 1x1 占位窗)
          geom=$(echo "$tree" | grep '"wxwork.exe"' | grep -v 'has no name' | grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' | awk -Fx '{split($2,a,"+"); if ($1*a[1]>mw*mh) {mw=$1; mh=a[1]}} END {print mw"x"mh}')
          tw=$(echo "$geom" | cut -dx -f1)
          th=$(echo "$geom" | cut -dx -f2)
          if [ "''${tw:-0}" -gt 50 ]; then
            # 无名、可见、宽或高超过顶层窗 → 视为故障 ARGB 合成子窗
            for id in $(echo "$tree" | grep 'has no name' | grep 'wxwork.exe' | grep -oE '^\s*0x[0-9a-f]+'); do
              id=''${id// /}
              stats=$(xwininfo -id "$id" -stats 2>/dev/null)
              [ "$(echo "$stats" | awk '/Map State/{print $3}')" = "IsViewable" ] || continue
              w=$(echo "$stats" | awk '/Width/{print $2}')
              h=$(echo "$stats" | awk '/Height/{print $2}')
              if [ -n "$w" ] && { [ "$w" -ge "$tw" ] || [ "$h" -ge "$th" ]; }; then
                xdotool windowunmap "$id" 2>/dev/null
              fi
            done
          fi
          # wine 托盘窗 (explorer.exe, 白色图标横条): unmap 隐藏。
          # 注意不能杀 explorer.exe 进程 —— 它是 wine 会话的桌面进程,
          # 杀掉会连带终止整个 wine 会话 (企业微信一起退出)。
          for id in $(echo "$tree" | grep 'explorer.exe' | grep -oE '^\s*0x[0-9a-f]+'); do
            tray_id=''${id// /}
            xdotool windowunmap "$tray_id" 2>/dev/null
          done
        fi
        sleep 3
      done
    '';
  };
in {
  systemd.user.services.wework-fix = {
    Unit = {
      Description = "WeCom (Bottles) ARGB subwindow auto-fix";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${weworkFixScript}/bin/wework-fix-subwindow";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
