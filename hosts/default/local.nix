{ lib, ... }:
{
  hostName = "wbb";                 # 主机名
  mainUser = lib.mkForce "wbb";     # 用户名 (覆盖模板默认 user)
}
