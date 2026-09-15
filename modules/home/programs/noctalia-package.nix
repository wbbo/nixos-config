# Noctalia 包 (本地补丁版) —— 供同层模块共用, 经 _module.args 暴露为 noctaliaPkg
#
# 补丁 patches/noctalia-annotation-ime.patch 实际含**五个独立关注点**, 上游合并其中
# 一个时其余仍然需要 —— 删除、升级或上游化之前逐条核对:
#
#   1. IME 接线 (上游功能缺口): 截图标注器未接 zwp_text_input_v3, 文字工具只消费
#      wl_keyboard 的 utf32 码点 → 主流 IME (fcitx5/ibus) 下中文完全打不了, 且标注器
#      不支持粘贴, 没有旁路。noctalia 本身有完整 TextInputService (launcher 在用),
#      补丁让标注器在文字编辑期间注册为焦点客户端, 走 preedit/commit。
#   2. 标注器文字编辑增强: 到画布边界自动折行 + 垂直钳制 (超出底部整体上移保持可见)
#      + Ctrl+A 全选 (高亮/替换/清除) + 换行感知的 caret 与候选窗定位。
#   3. 拖动残影修复 (上游 bug): 脏矩形越界时 copyArgb32RectToRgba / updateSubImage
#      对越界矩形整体拒绝更新, 屏幕残留旧像素; 改为裁剪到边界后上传。与 IME 无关,
#      可独立上游。
#   4. 文本度量: 边界/光标改用 Pango 末行 caret 位置 —— 折行后块级宽高 (最长行宽 +
#      整块高) 不再代表文本末尾。
#   5. 预编辑 (preedit) 渲染: 标注器声明 PREEDIT_SHOWN 却从不绘制, 而该 hint 是
#      "客户端自己画"的承诺 —— fcitx5 等据此把预编辑从自己的窗口里撤走, 结果拼音
#      **两边都不显示** (候选窗正常, 但看不到正在输入什么)。补丁现在把预编辑并入
#      Pango layout (提交文字之后), 并在 commit/取消/IME 重置时清干净。
#      样式刻意**不加下划线** —— 与 noctalia 自己的文本框 (launcher 把预编辑 insert
#      进值里原样渲染) 保持一致; 画布上加下划线读起来像标注样式而非输入状态。
#
# 基础版本: 补丁在上游 2856ec3 上开发, 在 flake input 锁定的 18bd8d63 上干净应用
# (仅行偏移 -7/-4, 无 fuzz/FAILED); 上游 input 升级后需重新核对应用情况。
#
# 上游合并全部内容后: 删本文件 + patch 文件 + 两处引用, 回到
# noctalia.packages.<system>.default。
{ pkgs, noctalia, ... }:
{
  _module.args.noctaliaPkg =
    noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../../../patches/noctalia-annotation-ime.patch ];
    });
}
