# mini-pc（server：不 include desktop / app；neverSleep 在 inventory.nix 的 settings 里）
#
# 硬件：AOOSTAR，Intel i9-13900H / 32G / Crucial P3 1TB NVMe。
# 下面取自实机 `nixos-generate-config --show-hardware-config`，文件系统改用 label
# 引用（与安装时的分区约定一致：boot / nixos / swap）。
{ den, ... }:
{
  den.aspects.Tobimune.includes = [ den.aspects.network.vpn.tailscale ];

  den.aspects.Tobimune.nixos =
    { config, lib, ... }:
    {
      boot.initrd.availableKernelModules = [
        "xhci_pci"
        "thunderbolt"
        "ahci"
        "nvme"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-intel" ];

      hardware.enableRedistributableFirmware = true;
      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-label/boot";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };

      swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];
    };
}
