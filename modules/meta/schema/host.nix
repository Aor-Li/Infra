{ lib, ... }:
{
  den.schema.host =
    { config, ... }:
    {
      options = {
        virt = lib.mkOption {
          type = lib.types.enum [
            "none"
            "vm"
            "wsl"
          ];
          default = "none";
          description = "The virtualization technology the host runs on, named after `systemd-detect-virt` output (`none` means bare metal).";
        };

        distro = lib.mkOption {
          type = lib.types.enum [
            "nixos"
            "darwin"
          ];
          default = "nixos";
          description = "The Linux distribution running on the host device.";
        };

        role = lib.mkOption {
          type = lib.types.enum [
            "desktop"
            "laptop"
            "server"
          ];
        };

      };
    };
}
