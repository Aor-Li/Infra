# nixos pc 
{ den, ... }:
{
  den.aspects.Enten = {
    includes = [
      den.aspects.desktop
      den.aspects.app
    ];

    nixos = {
      # FIXME: 临时使用的占位配置，在实机上生成 hardware-configuration 后重写
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
}
