# 主用户用户名 —— 全配置唯一的硬编码点。
#
# 修改此 option 的默认值即可整体自定义主用户名, 以下位置全部跟随:
#   - users.users.<name>            (系统账户)
#   - home-manager.users.<name>     (Home Manager 用户)
#   - greetd 登录用户
#   - 家目录路径 /home/<name>
#   - git 身份 / Firefox profile 名 / 壁纸目录 等
#
# 覆盖方式 (hosts/*/configuration.nix 中):
#   { config, ... }: { mainUser = lib.mkForce "alice"; ... }
{ lib, ... }:
{
  options.mainUser = lib.mkOption {
    type = lib.types.str;
    default = "user";
    example = "alice";
    description = "主用户用户名, 用于系统账户 / Home Manager / greetd / 家目录路径等";
  };
}
