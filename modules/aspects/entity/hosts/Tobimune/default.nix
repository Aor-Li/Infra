# mini-pc：常驻的 server（sshd、永不休眠，见 inventory.nix），同时接显示器当 niri 桌面用。
#
# host 上的 include 一次喂两侧，见 Enten/default.nix。
#
# 硬件：AOOSTAR，Intel i9-13900H（Iris Xe 核显）/ 32G / Crucial P3 1TB NVMe，板载 Wi-Fi + 蓝牙。
# 下面取自实机 `nixos-generate-config --show-hardware-config`，文件系统改用 label
# 引用（与安装时的分区约定一致：boot / nixos / swap）。
{ den, ... }:
{
  den.aspects.Tobimune.includes = [
    den.aspects.network.vpn.tailscale
    den.aspects.system.hardware.audio
    den.aspects.system.hardware.bluetooth
    den.aspects.desktop
    den.aspects.app
  ];

  den.aspects.Tobimune.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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

      # Iris Xe 的 VA-API 驱动：浏览器 / 播放器的视频硬解
      hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];

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
