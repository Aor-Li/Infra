{ lib, ... }:
{
  den.schema.host =
    { config, ... }:
    {
      options = {
        env = lib.mkOption {
          type = lib.types.enum [
            "physical"
            "virtual"
            "wsl"
          ];
          default = "physical";
          description = "The environment in which the host device is running.";
        };

        distro = lib.mkOption {
          type = lib.types.enum [
            "nixos"
            "darwin"
          ];
          default = "nixos";
          description = "The Linux distribution running on the host device.";
        };

      };
    };
}
