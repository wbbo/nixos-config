# 系统级程序与软件包
{ pkgs, ... }:
{
  ### 基础程序(系统级安装;/etc/shells、vendor 补全由此注册)
  # git / neovim / kitty / firefox 等用户程序由 Home Manager 统一管理(见 modules/home)
  # 注: programs.git.enable 只是把 git 包放系统环境 + 生成 /etc/gitconfig,
  # 不涉及用户配置 (~/.gitconfig 仍归 HM); 二者并存无冲突。
  programs = {
    bash.enable = true;
    fish.enable = true;
    # git-lfs: 装包 + /etc/gitconfig 自动写 filter.lfs (clean/smudge/process)。
    # 系统默认 git 不带 lfs, git lfs 子命令会报 "'lfs' 不是一个 git 命令"。
    # package 换 git.override: svnSupport 加 git svn 子命令 (公司仓库走
    # SVN); withLibsecret 加凭据助手 (HTTPS 凭据存 GNOME keyring);
    # withSsh 硬编码 ssh 路径 (systemd 单元环境不依赖 PATH)。
    # 与 HM programs.git.package 参数一致 → 同一 store 路径, 只有一份 git。
    git = {
      enable = true;      # gitconfig 生成的必需前提 (模块源码 mkIf cfg.enable)
      lfs.enable = true;
      package = pkgs.git.override {
        svnSupport = true;
        withLibsecret = true;
        withSsh = true;
      };
    };
  };

  ### 系统软件包(参考 nixos-niri-noctalia)
  environment.systemPackages = with pkgs; [
    ### 系统工具
    btrfs-assistant # Snapper/btrfs 图形管理 (Qt)
    pciutils
    usbutils
    curl
    jq
    yq
    wget
    cachix
    btrfs-progs

    ### 多媒体
    ffmpeg-full
    libva-utils

    ### 办公
    # LibreOffice: nixpkgs 一等公民 + 原生 Wayland (GTK4/VCL 后端), 纯 Wayland
    # 下没有额外兼容层。默认 langs 已含 zh-CN (见 nixpkgs
    # pkgs/applications/office/libreoffice/default.nix 的 langs 列表), 中文
    # 界面随包附带, 无需 override。
    libreoffice
    # 注: onlyoffice-desktopeditors 与 wpsoffice 曾于 2026-09-13 一并安装对比,
    # 两者均已移除, 原因:
    #   OnlyOffice —— FHS env 内中文字体回退有问题, PPT 里输入中文显示方框。
    #   WPS      —— 自带私有 Qt 5.12, 不支持 niri 给 4K 屏选的 1.5 分数缩放,
    #               界面字体过小 (需用户级 wrapper 设 QT_FONT_DPI=144 绕行);
    #               且其 Option Center 用 Qt5 WebKit 渲染, 中文全显方框。
    # 两者都属"能用但要持续绕行"的状态, 日常文档 LibreOffice 已足够覆盖。
    # 若日后需要更好的 MS 格式保真, 优先考虑 rather than WPS:
    #   onlyoffice-desktopeditors (AGPL 自由软件, 但需先解决字体回退)。

    ### Wayland 工具链
    wl-clipboard
    # 剪贴板持久化守护: Wayland 剪贴板内容由"提供者进程"持有, 工具一退即空
    # (GTK4 应用如 satty/Nautilus 的复制都这样, 详见 satty-config.toml 注释)。
    # 它常驻接管内容, 使复制跨进程存活; 由 niri spawn-at-startup 拉起
    # (config.kdl 启动项区块), 不用 systemd 单元 —— 它依赖 Wayland 会话。
    wl-clip-persist
    grim
    slurp
    # satty override: nixpkgs 停在上游 0.20.1, 而 auto-copy (标注改动即自动
    # 复制, 0.21.0 起引入) 是截图工作流的关键, 故拉 0.22.0 源码本地构建。
    # 与 nixpkgs 原表达式的差异:
    #   1. src 换 Satty-org/Satty (上游仓库已从 gabm/Satty 迁移)
    #   2. cargoDeps 必须显式覆盖, 不能改 cargoHash —— buildRustPackage 走
    #      finalAttrs, cargoHash 在求值期就折叠成 cargoDeps, overrideAttrs
    #      事后改 cargoHash 无效 (实测仍按旧 hash 校验并报 mismatch)
    #   3. postInstall 去掉 installShellCompletion —— 0.22 不再随源码携带
    #      completions/ 目录 (改由 build.rs 生成), 照搬旧命令会构建失败
    (satty.overrideAttrs (old: rec {
      version = "0.22.0";
      src = pkgs.fetchFromGitHub {
        owner = "Satty-org";
        repo = "Satty";
        rev = "v${version}";
        hash = "sha256-76J4ZlBKeow2sWs1SeSkE8R2fKRTFD+B+7Vx3nbbQxY=";
      };
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit src;
        name = "satty-${version}-vendor";
        hash = "sha256-R8I8eZ8vy6w1DGNrkP9Os2tAOIetqXCyn0cxWpk9F+w=";
      };
      postInstall = ''
        install -Dt $out/share/icons/hicolor/scalable/apps/ assets/satty.svg
      '';
    }))                    # 截图标注 (0.22.0, 见上方 override 说明)

    ### 美化 / 状态
    starship
    bibata-cursors

    ### 文件管理
    # Nautilus override: 把 nautilus-python 加载器软链进**它自己的**扩展目录。
    # Nautilus 只在自身 store 路径的 lib/nautilus/extensions-4/ 扫描扩展
    # (二进制内该路径是单一硬编码值, 不搜索 XDG_DATA_DIRS), 不注入则第三方
    # python 扩展 (nautilus-open-any-terminal) 永远加载不到 —— 这正是"在终端
    # 中打开"只能退化为 scripts 子菜单的原因。override 是 NixOS 下实现顶层
    # 原生菜单项的唯一途径; 路径为 Nautilus 稳定约定, 升级时留意即可。
    (pkgs.nautilus.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        ln -sf ${pkgs.nautilus-python}/lib/nautilus/extensions-4/libnautilus-python.so \
          $out/lib/nautilus/extensions-4/libnautilus-python.so
      '';
    }))
    yazi

    ### 终端装饰
    cmatrix

    ### 无线 / 网络诊断
    iw                         # Wi-Fi 接口/链路质量/扫描
    # networkmanagerapplet 已移除: 托盘网络图标由 noctalia network widget 提供
    # (左键 control-center 网络面板 / 右键开关无线), 避免外部图标与 noctalia 观感不一致

    ### 基础网络调试
    dnsutils                   # dig / nslookup
    iputils                    # ping / traceroute
  ];
}
