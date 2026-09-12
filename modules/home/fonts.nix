# 用户级 fontconfig —— 补系统级做不到的字体别名
#
# 为什么不用 NixOS 的 fonts.fontconfig.localConf: 它生成 /etc/fonts/local.conf,
# 由 conf.d/51-local.conf 引入, 优先级 51 —— 会被后续规则 (60-latin.conf 等)
# 覆盖。实测同一份规则写在系统级完全不生效 (Symbol 仍解析到 Noto Sans CJK SC),
# 移到用户级 ~/.config/fontconfig/fonts.conf (优先级最高) 后立刻生效。
#
# 用途: 把 MS 专有符号字体名 (Symbol / MT Extra) 指向 STIX Two Math —— WPS 的
# 启动自检据此判断公式符号字体是否齐备, 缺失时弹 "Some formula symbols might
# not be displayed correctly"。注意这是"消除自检告警"层面的修复; 公式渲染是否
# 真的完美, 仍需实际打开公式编辑器确认 (MT Extra 是 MS 专有字体, STIX 未必
# 逐字形对应)。
#
# force = true: 本文件曾为对照实验手工创建过同名普通文件, 而 HM 默认拒绝覆盖
# 已存在文件 (报 "Existing file ... would be clobbered" 并让整个激活失败)。
{ ... }:
{
  xdg.configFile."fontconfig/fonts.conf" = {
    force = true;
    text = ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
      <fontconfig>
        <match target="pattern">
          <test name="family"><string>Symbol</string></test>
          <edit name="family" mode="assign" binding="strong"><string>STIX Two Math</string></edit>
        </match>
        <match target="pattern">
          <test name="family"><string>MT Extra</string></test>
          <edit name="family" mode="assign" binding="strong"><string>STIX Two Math</string></edit>
        </match>
      </fontconfig>
    '';
  };
}
