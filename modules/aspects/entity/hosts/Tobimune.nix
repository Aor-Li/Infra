# mini-pc
{ den, ... }:
{
  den.aspects.Tobimune = {
    nixos = {
      # FIXME: 临时使用的占位配置，在aoostar机器上生成后重写
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

  den.hosts.x86_64-linux.Tobimune.settings.system.power.sleep.neverSleep = true;
}
