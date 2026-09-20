# ssh-temp-password —— SSH 临时开放密码登录的动态开关 (sudo 免密)
#
# 配套: services.nix 的全局 key-only (PasswordAuthentication no) +
# extraConfig 的 Match Group temp-ssh-password (组内放行密码)。
# 本命令的 on/off 就是把 mainUser 加进/移出该组 —— sshd 每次认证实时查询
# 组成员, 无需 reload。
#
# 用法: sudo ssh-temp-password {on|off|status}
#   on      mainUser 加入 temp-ssh-password 组 → 22 端口可用密码登录
#   off     移出组 → 回到 key-only
#   status  组成员 + 当前生效状态
#
# 语义: 临时授权 —— rebuild/重启后组成员可能被声明复位 (users.groups
# members 留空), 无论如何 off 都能手动收回。
{ config, pkgs, ... }:
let
  sshTempPassword = pkgs.writeShellApplication {
    name = "ssh-temp-password";
    runtimeInputs = [ pkgs.shadow pkgs.coreutils pkgs.gnugrep ];
    # status/off 分支的 grep 无匹配属正常, 不开 errexit
    text = ''
      GROUP="temp-ssh-password"
      TARGET="${config.mainUser}"

      in_group() { id -nG "$TARGET" 2>/dev/null | grep -qw "$GROUP"; }

      cmd="''${1:-status}"
      case "$cmd" in
        on)
          if in_group; then
            echo "已处于开放状态 ($TARGET 已在 $GROUP 组)"
          else
            usermod -aG "$GROUP" "$TARGET"
            echo "已临时开放密码登录 (22 端口, $TARGET@本机, 密码 = 主用户密码)"
            echo "注意: 已有会话不受影响; 新登录生效; 收回: sudo ssh-temp-password off"
          fi
          ;;
        off)
          if in_group; then
            gpasswd -d "$TARGET" "$GROUP" >/dev/null
            echo "已收回 —— SSH 回到 key-only"
          else
            echo "本就处于关闭状态"
          fi
          ;;
        status)
          if in_group; then
            echo "状态: 开放 ($TARGET 在 $GROUP 组, 22 端口可密码登录)"
          else
            echo "状态: 关闭 (key-only; $TARGET 不在 $GROUP 组)"
          fi
          ;;
        *)
          echo "用法: ssh-temp-password {on|off|status}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ sshTempPassword ];

  security.sudo.extraRules = [
    {
      users = [ config.mainUser ];
      commands = [
        {
          command = "${sshTempPassword}/bin/ssh-temp-password";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
