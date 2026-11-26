# 关掉它你会失去：蓝牙——耳机 / 键鼠等蓝牙外设的配对与连接。
#
# 不在 hardware.nix 的 includes 里：只有带蓝牙模块的实机才需要，由 entity 显式 include。
{
  den.aspects.system.hardware.bluetooth.nixos = {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}
