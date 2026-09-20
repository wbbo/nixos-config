# proxy-lan —— mihomo LAN 共享代理的动态开关 (sudo 免密)
#
# 分工: mihomo 模板 allow-lan: true 把 7890 绑到所有接口 ("监听"交给应用);
# 访问控制交给防火墙 —— networking.firewall 默认拒绝入站且 **不放行** 7890,
# 本命令运行时动态插拔 iptables INPUT 放行规则。默认 (无规则) = LAN 不可
# 访问; 规则不持久化, 重启自动回到关闭 (安全默认)。
#
# 用法: sudo proxy-lan {on|off|status} [CIDR...]
#   on      放行 (缺省 CIDR = 全部来源 v4+v6; 传 192.168.1.0/24 等可限网段,
#           冒号开头的按 IPv6 走 ip6tables)
#   off     收回全部 proxy-lan 规则
#   status  当前规则 + mihomo 监听 + 本机 LAN IP (手机端可直接照填)
#
# iptables -I INPUT 插在链首, 先于 NixOS firewall (iptables 模式) 的默认
# 拒绝生效; 规则带 --comment "proxy-lan" 便于 -S 精确识别删除。注意 v4/v6
# 规则必须分别用 iptables/ip6tables 删除 —— 两者的 -S 输出长得一样 (都写作
# "-A INPUT ..."), 混删会静默失败。
{ config, pkgs, ... }:
let
  proxyLan = pkgs.writeShellApplication {
    name = "proxy-lan";
    runtimeInputs = [ pkgs.iptables pkgs.iproute2 pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
    # bashOptions 不设 —— 默认 errexit/nounset/pipefail (只认长名, 短名 "u"
    # 生成非法的 `set -o u`, 严格模式静默失效, 同 adapt.sh 踩过的坑)。脚本内
    # 所有可能无匹配的 grep 均带 || true 或处于命令替换, errexit 安全。
    text = ''
      MARK="proxy-lan"
      PORT="7890"

      usage() {
        echo "用法: proxy-lan {on|off|status} [CIDR...]" >&2
        exit 2
      }

      v4_rules() { iptables -S INPUT 2>/dev/null | grep -F -- "--comment $MARK" || true; }
      v6_rules() { ip6tables -S INPUT 2>/dev/null | grep -F -- "--comment $MARK" || true; }

      # 删除全部 proxy-lan 规则 (v4/v6 分开删, 见文件头注释)。
      # ''${rule#"-A "} 的无引号分词是有意的: 把 "INPUT -p tcp ..." 拆回多个
      # 参数传给 iptables -D。
      flush_rules() {
        while read -r rule; do
          [ -n "$rule" ] || continue
          # shellcheck disable=SC2086
          iptables -D INPUT ''${rule#"-A "} 2>/dev/null || true
        done < <(v4_rules)
        while read -r rule; do
          [ -n "$rule" ] || continue
          # shellcheck disable=SC2086
          ip6tables -D INPUT ''${rule#"-A "} 2>/dev/null || true
        done < <(v6_rules)
      }

      cmd="''${1:-}"
      [ -n "$cmd" ] || usage
      shift

      case "$cmd" in
        on)
          flush_rules
          if [ $# -gt 0 ]; then
            for cidr in "$@"; do
              case "$cidr" in
                *:*)
                  ip6tables -I INPUT -p tcp -s "$cidr" --dport "$PORT" -m comment --comment "$MARK" -j ACCEPT
                  ;;
                *)
                  iptables -I INPUT -p tcp -s "$cidr" --dport "$PORT" -m comment --comment "$MARK" -j ACCEPT
                  ;;
              esac
            done
          else
            iptables -I INPUT -p tcp --dport "$PORT" -m comment --comment "$MARK" -j ACCEPT
            ip6tables -I INPUT -p tcp --dport "$PORT" -m comment --comment "$MARK" -j ACCEPT
          fi
          echo "已放行 LAN → :$PORT (本机重启或 proxy-lan off 前有效)"
          ;;
        off)
          flush_rules
          echo "已收回, LAN 不再能访问 :$PORT"
          ;;
        status)
          echo "== proxy-lan 规则 =="
          if [ "$(id -u)" = 0 ]; then
            rules="$( { v4_rules; v6_rules; } )"
            if [ -n "$rules" ]; then
              echo "$rules"
            else
              echo "(无 —— LAN 访问 :$PORT 为关闭状态)"
            fi
          else
            echo "(需 root 查看 —— sudo proxy-lan status)"
          fi
          echo "== mihomo 监听 =="
          ss -tln | grep ":$PORT " || echo "(mihomo 未监听 :$PORT)"
          echo "== 本机地址 (客户端代理填这里) =="
          ip -4 -o addr show scope global | awk '{print "  " $2 ": " $4}'
          ;;
        *)
          usage
          ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ proxyLan ];

  security.sudo.extraRules = [
    {
      users = [ config.mainUser ];
      commands = [
        {
          command = "${proxyLan}/bin/proxy-lan";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
