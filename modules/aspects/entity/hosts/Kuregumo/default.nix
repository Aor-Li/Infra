# macbook nixos vm with desktop
# include 同时作用于系统侧与 home 侧，见 Enten/default.nix。
{ den, ... }:
{
  den.aspects.Kuregumo = {
    includes = [
      den.aspects.desktop
      den.aspects.app
      den.aspects.dev.editor.vscode
      den.aspects.service.remote.sunshine
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
}
