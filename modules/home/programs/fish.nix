# fish shell 用户配置
# 二进制与 /etc/fish vendor 补全由**系统级** programs.fish.enable 提供
# (modules/nixos/packages.nix), 此处 programs.fish 只负责用户级:
# ~/.config/fish/config.fish 与 functions/。
#
# 为什么启用 HM 的 fish 模块 (2026-09-29): home.sessionVariables 在 HM 里只
# 打成一个包 (modules/home-environment.nix:656 home.sessionVariablesPackage →
# etc/profile.d/hm-session-vars.sh), **自身没有任何激活逻辑**, 必须由某个 shell
# 模块 (programs.bash/zsh/fish) 去 source 才有意义。此前 fish 是用
# xdg.configFile 手挂 config.fish、绕过了 fish 模块, 于是 EDITOR/VISUAL/
# XMODIFIERS/QT_IM_MODULES/JAVA_HOME/CARGO_HOME... 那批变量连文件都没被引用
# (实测: 变量包内 12 条齐全, 但 fish conf.d 与各 profile 零 source), 是死配置。
# 启用后 HM 生成的 config.fish 会**无条件** source hm-session-vars.fish
# (位置在 status is-login / is-interactive 判断之前) —— 而 niri-session 正是以
# `exec -l fish -c 'niri-session -l'` (非交互 login shell) 运行, 变量由此进入
# niri 会话, 再经 niri-session 的 `systemctl --user import-environment` 带入
# systemd user manager。这正是 niri 官方文档推荐的"要全局可见就放 login shell
# 配置"路径 —— config.kdl 的 environment{} 块官方明确不传播到 systemd。
{ pkgs, ... }:
let
  # top 专用 terminfo (topm): procps top 的表头反白写死 (Cap_reverse),
  # 深色终端下 = 白底深字 (kitty 中表头"发虚/白底"的根源)。
  # 把 rev/smso 从反白 \E[7m 改为加粗 \E[1m, 表头变深底浅字。
  # topm.terminfo 由 `infocmp -x kitty` 导出后改 rev/smso 得到。
  topm = pkgs.runCommand "topm-terminfo" { nativeBuildInputs = [ pkgs.ncurses ]; } ''
    tic -x -o $out ${./topm.terminfo}
  '';
in {
  # fzf 集成依赖 (NyxNiri 移植: 历史/文件/Git 搜索 + nix 包搜索)
  home.packages = [ pkgs.fzf pkgs.fd pkgs.bat ];

  # 链接自定义 terminfo 到 ~/.terminfo, top alias 用 TERM=topm 生效
  home.file.".terminfo/t/topm".source = "${topm}/t/topm";

  programs.fish = {
    enable = true;

    # shellInit = **无条件**执行块 (非交互/非 login 也跑)。PATH 必须放这里:
    # niri-session 走的是非交互 login shell, 只有无条件块才保证 ~/.local/bin
    # 进到 niri 及其所有子进程 (claude / cc-switch 等脚本装 CLI 靠它);
    # EDITOR/VISUAL 不再单独设 —— 已由 home.sessionVariables 统一提供。
    shellInit = ''
      # 取消欢迎语
      set -g fish_greeting

      # ~/.local/bin: 原生安装脚本装的 CLI (claude / cc-switch 等)
      fish_add_path ~/.local/bin
      # rustup 的 cargo/rustc 经 rustup toolchain 装到 ~/.cargo/bin
      fish_add_path ~/.cargo/bin
    '';

    # 交互式才需要: prompt 初始化
    interactiveShellInit = ''
      # Starship prompt
      starship init fish | source
    '';

    shellAliases = {
      cat = "bat --paging=never";
      ls = "eza --icons";
      grep = "grep --color=auto";
      ll = "eza -la --git --icons";
      lt = "eza --tree --icons --level=2";
      vim = "nvim";
      ":q" = "exit";
      cls = "clear";
      top = "TERM=topm LANG=C command top";
      claude = "claude --dangerously-skip-permissions";
      cs = "cc-switch";
    };

    # 独立函数文件 (~/.config/fish/functions/<名>.fish): fish 自动按需加载,
    # 非交互调用同样可用 (原先是全塞在 config.fish 里无条件定义)
    functions = {
      niri-res = {
        body = ''
      # niri 分辨率/缩放: 运行时修改 + 持久化
      # (state 写入 ~/.local/state/niri-resolution|niri-scale, 下次启动由 niri-apply-resolution 应用)
        set -q argv[1]; or begin
            echo "用法: niri-res <mode>         如 niri-res 1920x1080@60"
            echo "      niri-res scale <scale>  如 niri-res scale 1.25"
            return 1
        end
        set output (niri msg outputs 2>/dev/null | grep -oP '^Output "\K[^"]+' | head -1)
        if test -z "$output"
            echo "错误: 找不到 niri 输出 (需在 niri 会话内运行)"
            return 1
        end
        if test "$argv[1]" = scale
            niri msg output $output scale "$argv[2]"; and echo "$argv[2]" > ~/.local/state/niri-scale
        else
            niri msg output $output mode "$argv[1]"; and echo "$argv[1]" > ~/.local/state/niri-resolution
        end
        '';
      };
      _fzf_history = {
        body = ''
      # ── fzf 集成 (NyxNiri 移植) ──────────────────────────────
      # Ctrl+R 历史搜索 / Alt+F 文件查找 / Alt+L Git Log / Alt+S Git Status
      # (Alt+F/S 覆盖 fish 默认 forward-word/sudo, 与 NyxNiri 一致)
        # --print0 + split0: NUL 切出整条命令作为单参数原样回填, 含空格/引号的历史行不会被重新分词破坏
        set -l cmd (history | fzf --height 40% --reverse --query (commandline -b) --prompt "历史 > " --print0 | string split0 -m1)[1]
        test -n "$cmd"; and commandline -r -- $cmd
        '';
      };
      _fzf_files = {
        body = ''
        set -l sel (fd --type f --hidden --exclude .git 2>/dev/null | fzf --height 40% --preview 'bat --color=always {} 2>/dev/null || head -50 {}' --prompt "文件 > ")
        # string escape: 含空格/元字符的路径重解析回单 token, 不再被拆成多个词
        test -n "$sel"; and commandline -r -- (string escape -- "$sel")
        '';
      };
      _fzf_git_log = {
        body = ''
        set -l sel (git log --oneline --color=always 2>/dev/null | fzf --height 40% --preview 'git show --color=always {1} 2>/dev/null | head -80' --prompt "git log > ")
        test -n "$sel"; or return
        set -l hash (string split -m1 " " "$sel")[1]
        commandline -r -- "git show $hash"
        '';
      };
      _fzf_git_status = {
        body = ''
        # git status --short 行格式为 "XY path" (X=已暂存列, Y=未暂存列, ??=未跟踪)
        # 旧实现用 string split 取第 2 词, 最常见行 " M path" 会得到 "M path" 导致 git 报错
        set -l sel (git status --short 2>/dev/null | fzf --height 40% \
            --preview 'set -l f (string sub -s 4 -- {}); set -l f (string split -m1 " -> " "$f")[1]
if string match -q "\"*\"" -- "$f"
    set f (string unescape -- (string sub -s 2 -e -1 -- "$f"))
end
if string match -q "??" -- (string sub -l 2 -- {})
    git diff --no-index --color=always /dev/null -- "$f" 2>/dev/null
else
    git diff HEAD --color=always -- "$f" 2>/dev/null
end | head -80' --prompt "git status > ")
        test -n "$sel"; or return
        # 跳过 "XY " 前缀取路径 (rename 行 "R  old -> new" 取旧路径, HEAD 中可 diff);
        # git 对含空格/特殊字符的路径输出 C 引用 (双引号包裹 + 反斜杠转义), 剥引号再反转义
        set -l f (string sub -s 4 -- "$sel" | string split -m1 " -> ")[1]
        if string match -q '"*"' -- "$f"
            # 注意: if 块内 set -l 是块级作用域, 用无 -l 的 set 修改外层变量
            set f (string unescape -- (string sub -s 2 -e -1 -- "$f"))
        end
        if string match -q "??" -- (string sub -l 2 -- "$sel")
            # 未跟踪文件: no-index 对 /dev/null 展示新增的全部内容
            commandline -r -- (string join " " "git diff --no-index /dev/null --" (string escape -- "$f"))
        else
            # 相对 HEAD 一条命令覆盖已暂存/未暂存/两者并存, 无需区分状态列
            commandline -r -- (string join " " "git diff HEAD --" (string escape -- "$f"))
        end
        '';
      };
      se = {
        body = ''
      # se: nixpkgs 模糊搜索 + fzf 交互安装 (nix profile install)
        set -l query (string join ' ' $argv)
        if test -z "$query"
            echo "用法: se <关键字>"
            return 1
        end
        # nix search 输出带 ANSI 色, 先去色再喂 fzf; 捕获组在 $attr[2]
        # 注意: Nix 转义 (反斜杠 x 十六进制 / 单引号对转义为双引号),
        # 空字符串参数改用双引号
        set -l pkgs (nix search nixpkgs "$query" 2>/dev/null \
            | string replace -ra '\\x1b\\[[0-9;]*m' "" \
            | fzf --multi --height 60% --prompt "📦 nixpkgs > ")
        test -n "$pkgs"; or return 0
        for p in $pkgs
            set -l attr (string match -r '^[^.]*\.[^.]+\.([^ ]+)' "$p")
            if test -n "$attr[2]"
                echo "→ 安装 nixpkgs#$attr[2]"
                command nix profile install "nixpkgs#$attr[2]"
            end
        end
        '';
      };
      fish_user_key_bindings = {
        body = ''
        bind \cr _fzf_history
        bind \eF _fzf_files
        bind \eL _fzf_git_log
        bind \eS _fzf_git_status
        '';
      };
    };
  };
}
