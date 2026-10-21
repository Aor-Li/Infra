# macbook nixos vm with desktop
# 系统侧 / home 侧两行 include 的含义见 Enten/default.nix。
{ den, ... }:
{
  den.aspects.Kuregumo = {
    includes = [
      den.aspects.desktop
      den.aspects.app
    ];

    nixos = {
      # FIXME: 临时使用的占位配置，在虚拟机中生成 hardware-configuration 后重写
      # （bootloader 由 system/boot 统一设置，这里不重复）
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-label/boot";
        fsType = "vfat";
      };
    };
  };

  den.aspects."aor@Kuregumo".includes = [
    den.aspects.desktop
    den.aspects.app
  ];
}
