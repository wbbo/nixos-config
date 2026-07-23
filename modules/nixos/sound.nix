# 音频:PipeWire(PulseAudio 的现代替代,Wayland 友好)
{ ... }:
{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    # JACK 兼容层(专业音频软件)
    jack.enable = true;
  };
}
