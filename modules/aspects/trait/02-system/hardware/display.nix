# 关掉它：外接显示器只剩系统给的那几档缩放，亮度与 HiDPI 都得手动点。
{ ... }:
{
  den.aspects.system.hardware.display = {

    darwin = {
      homebrew.casks = [ "betterdisplay" ];
    };

    # todo: 设置目前在 GUI 里配。BetterDisplay 的 per-display 键按 EDID/序列号拼，
    # 声明化收益不如可读性损失，等真有多机共用的配置再上 targets.darwin.defaults。
  };
}
