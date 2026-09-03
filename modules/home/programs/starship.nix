# Starship 提示符 —— 完全声明式管理
#
# Noctalia 的 starship 模板渲染已关闭 (见 noctalia.nix): 它与自定义 powerline
# palette 'colors' 冲突 (Noctalia 会把 palette 行改成 "noctalia", 导致 color_*
# 引用失效 → 无彩色)。渲染关闭后无程序运行时改写此文件, 直接 symlink 到
# store 即可: 自动建父目录 (首次 boot 空家目录也安全)、幂等、内容恒定,
# 取代原先 activation 钩子 install 覆盖的方案 (其 install 缺 -D 曾致首次
# boot 激活失败, 引发 niri 默认配置接管冲突)。
{
  xdg.configFile."starship.toml".source = ./starship.toml;
}
