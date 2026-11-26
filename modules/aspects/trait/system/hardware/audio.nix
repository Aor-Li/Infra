# 关掉它你会失去：声音——PipeWire 音频服务及其 PulseAudio / ALSA 兼容层，音量控制与媒体播放都没有输出。
#
# 不在 hardware.nix 的 includes 里：system 是全体基线，而声音不是所有机器都需要，由 entity 显式 include。
{
  den.aspects.system.hardware.audio.nixos =
    { pkgs, ... }:
    {
      # rtkit 给 PipeWire 实时调度优先级，避免负载高时爆音
      security.rtkit.enable = true;
      services.pulseaudio.enable = false;

      services.pipewire = {
        enable = true;
        pulse.enable = true;
        alsa.enable = true;
        # 32 位 ALSA 只存在于 x86_64（Steam / Wine 一类程序要它），其他架构开了会报错
        alsa.support32Bit = pkgs.stdenv.hostPlatform.isx86_64;
      };
    };
}
