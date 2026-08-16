# 星环菜单 (M3 radial menu) + Scratchpad —— NyxNiri 脚本移植, NixOS 声明式打包
#
# NixOS 哲学落地点:
# - 脚本全部入 repo (modules/home/programs/scratchpad/), 由 nix 打包为 store 产物,
#   依赖 (python/pygobject/gtk-layer-shell/jq/tmux) 由 nix 提供, 不依赖系统散装安装。
# - 菜单配置 items.toml 声明式部署, 修改走 repo + rebuild (声明式, 可复现)。
# - menu.py 内部硬编码引用的 toggle 路径 (~/.config/niri/scripts/niri-scratch-toggle.sh)
#   由 xdg.configFile 指向 store 可执行脚本, 保持脚本自洽无需改动源码。
{ pkgs, lib, ... }:
let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

  # GI typelib 搜索路径: pygobject 需在 GI_TYPELIB_PATH 找到全部依赖 typelib。
  # lib.getLib 取 .out/.lib 输出 (避免解析到无 typelib 的 -bin/-dev 输出)。
  # 覆盖 GTK3 栈完整依赖链 (Gtk/Gdk/GdkX11/GdkPixbuf/Pango/Cairo/HarfBuzz/Atk/GLib/Gio/xlib…)。
  giDeps = [
    pkgs.gtk3 pkgs.gtk-layer-shell pkgs.pango pkgs.cairo pkgs.gdk-pixbuf
    pkgs.harfbuzz pkgs.gobject-introspection pkgs.glib pkgs.atk pkgs.fontconfig pkgs.libxcb
  ];
  giPath = lib.concatStringsSep ":" (map (p: "${lib.getLib p}/lib/girepository-1.0") giDeps);

  # M3 星环启动器 (Material 3 radial menu, 零常驻按需执行, 配色读 Noctalia palette 缓存)
  star-menu = pkgs.stdenv.mkDerivation {
    pname = "niri-scratch-menu";
    version = "1.0.0";
    src = ./scratchpad;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    buildInputs = giDeps;
    installPhase = ''
      mkdir -p $out/bin $out/share/niri-scratch-menu
      # menu.py 放 share (不可执行): 保持 python 直接解析源码
      install -m 0644 $src/menu.py $out/share/niri-scratch-menu/menu.py
      makeWrapper ${pythonEnv}/bin/python $out/bin/niri-scratch-menu \
        --prefix GI_TYPELIB_PATH : "${giPath}" \
        --add-flags "$out/share/niri-scratch-menu/menu.py"
    '';
  };

  # Scratchpad 生命周期控制器 (kitty 持久浮动终端 + tmux 保活会话, 跨工作区搬运)
  toggle = pkgs.writeShellApplication {
    name = "niri-scratch-toggle";
    runtimeInputs = [ pkgs.jq pkgs.kitty pkgs.tmux pkgs.niri pkgs.fish pkgs.coreutils ];
    text = builtins.readFile ./scratchpad/toggle.sh;
  };
in {
  home.packages = [ star-menu toggle ];

  # 星环菜单配置 (菜单项/搜索引擎/快捷键, 修改走 repo 声明式)
  xdg.configFile."niri/scratchpad-items__custom__.toml".source = ./scratchpad/items.toml;

  # menu.py 硬编码引用的 toggle 路径, 部署为 store 可执行脚本 (只读, 由 nix 管理)
  xdg.configFile."niri/scripts/niri-scratch-toggle.sh".source = "${toggle}/bin/niri-scratch-toggle";
}
