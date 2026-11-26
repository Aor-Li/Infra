{ den, ... }:
{
  # system 属于全体基线，这里只列所有机器都需要的叶子。
  # 可选叶子（audio / bluetooth）由 entity 按硬件显式 include，不进这里。
  den.aspects.system.hardware.includes = [
    den.aspects.system.hardware.display
    den.aspects.system.hardware.peripheral
  ];
}
