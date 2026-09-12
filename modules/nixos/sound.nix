# 音频:PipeWire(PulseAudio 的现代替代,Wayland 友好)
{ pkgs, ... }:
{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    # JACK 兼容层(专业音频软件)
    jack.enable = true;

    ### Redmi 电脑音箱 (MV-SILICON USB 声卡) 的「音量悬崖」workaround ——
    ### 该卡硬件混音器是纯增益型刻度 (raw 0..4096 = 0dB..+16dB): 没有负 dB
    ### 衰减区, 且最低档 raw 0 实测完全静音 (2026-09-10 实测, 名义 0dB)。
    ### WirePlumber 默认把软件音量按 cubic 曲线映射到该刻度, 实测
    ### hw_dB = 16 + 60·log10(v) 逐点吻合; 当 v < 10^(-16/60) ≈ 0.54 时
    ### 结果跌破刻度下限被 clamp 到 raw 0 → 全系统静音。
    ### 现象: Noctalia/wpctl 音量 ≤ 54% 完全无声, 55% 起才出声 ——
    ### "调小音量反而静音", 且 sink 显示值正常, 极难排查。
    ### soft-mixer = true: 音量全部改走 PipeWire 软件层衰减, 硬件增益
    ### 不再被改写 (实测 set-volume 0.1~1.0 全程 hw 稳定 4096), 悬崖消失,
    ### 0~100% 全范围可用; 100% 时仍是 +16dB 满增益, 响度不变。
    wireplumber.extraConfig."51-redmi-soft-mixer" = {
      "monitor.alsa.rules" = [
        {
          matches = [ { "device.name" = "~alsa_card.usb-MV-SILICON_Redmi.*"; } ];
          actions.update-props."api.alsa.soft-mixer" = true;
        }
      ];
    };
  };

  ### 承上: soft-mixer 后 WirePlumber 不再写硬件增益 (原文 "leaving the
  ### hardware mixer untouched"), 该值退化为设备/驱动上电默认 —— 不保证是
  ### 满值, 若停在最低档则照样整体静音。故在声卡出现时直接拉满 (+16dB),
  ### 把音量完全交给 PipeWire 软件层 (幂等: 设成同值无副作用)。
  ### 注意 %% : udev 的 RUN 值里 % 是替换字符, 写成 100% 会被 udevadm verify
  ### 判为 "invalid substitution type" 导致整个 udev-rules 构建失败, 必须
  ### 双写转义 (已实测 verify 通过, 且运行时正确展开为 100%)。
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="sound", KERNEL=="card*", ATTR{id}=="Redmi", RUN+="${pkgs.alsa-utils}/bin/amixer -c Redmi sset PCM 100%%"
  '';
}
