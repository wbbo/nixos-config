# HMCL (Hello Minecraft! Launcher) —— Minecraft 启动器 / 版本与整合包管理
#
# 分工: 本机无官方启动器; HMCL 管 Minecraft 本体、版本隔离、模组加载器
# (Forge/Fabric/Quilt/NeoForge) 与账户。与 Lutris/Steam 无关 (那两个管别的平台)。
#
# 为什么用 nixpkgs 的包, 而不是官网的 HMCL-x.y.z.sh (2026-09-16 实测):
# 官网 .sh 是"预编译 JavaFX + 探测系统 JDK"的自解压脚本, 在 NixOS 上两处
# 必然失败:
#   1. 下载后没有执行位 (0644) —— `./` 执行与文件管理器双击都报"权限不够";
#   2. `bash HMCL-x.y.z.sh` 绕过执行位后, JavaFX 类能加载, 但原生库找不到:
#        UnsatisfiedLinkError: no glassgtk3 in java.library.path:
#          /usr/java/packages/lib:/usr/lib64:/lib64:/lib:/usr/lib
#      NixOS 上 /usr/lib、/usr/lib64、/lib、/usr/java 全不存在, /etc/ld.so.cache
#      里 libgtk 条目数为 0 (实测) —— 即便把 .so 翻出来, 它依赖的
#      libgtk-3/libX11 同样无处可寻。预编译包 vs NixOS 路径模型的结构性冲突,
#      不是 HMCL 的 bug, 修不了也不值得修。
# nixpkgs 的 hmcl (版本与官网同步, 当前 3.16.3) 已把这套全接好:
#   jdk.override { enableJavaFX = true; }   —— JavaFX 编进 JDK, 无需运行时下载
#   --set LD_LIBRARY_PATH <GTK/X11/GL/ALSA 全套> + -Djdk.gtk.version=3
#   --run 'cd $HOME'  —— HMCL 游戏目录默认取相对路径 .minecraft, 靠这行落在家目录
#
# 持久化: ~/.local/share/hmcl (启动器设置/账户) 与 ~/.minecraft (游戏本体) 已在
# modules/home/persist.nix 声明; 若在 HMCL 里改用别的游戏目录, 记得同步那条。
{ pkgs, ... }:
{
  home.packages = [ pkgs.hmcl ];
}
