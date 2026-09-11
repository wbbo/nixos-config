# 邮件客户端 Thunderbird
# Wayland: niri 的 config.kdl environment 块已设 MOZ_ENABLE_WAYLAND=1 与
# 会话级输入法变量 (GTK_IM_MODULE=fcitx), 无需在此重复。
# profile 只声明骨架 (isDefault), 不配账户: 邮箱/服务器/密码属个人数据,
# 首次启动时在 TB 界面里添加。HM 只生成 profiles.ini 与 user.js, 不碰
# prefs.js —— 手动改的设置不会被 rebuild 覆盖 (区别于 gh 的权威源语义)。
# 数据目录 ~/.thunderbird (账户配置/本地邮件/地址簿) 已在 persist.nix
# 持久化, 重装/回滚后保留。
{ mainUser, ... }:
{
  programs.thunderbird = {
    enable = true;
    profiles.${mainUser}.isDefault = true;
  };
}
