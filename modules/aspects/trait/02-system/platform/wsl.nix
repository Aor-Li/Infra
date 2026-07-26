{ den, inputs, lib, ... }:
{
  flake-file.inputs = {
    nixos-wsl.url = "github:nix-community/nixos-wsl";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.system.core.wsl =
    { host, ... }:
    {
      nixos = {
        imports = [ inputs.nixos-wsl.nixosModules.wsl ];
        wsl = lib.mkIf (host.env == "wsl" && host.distro == "nixos") {
          enable = true;
          useWindowsDriver = true;
          startMenuLaunchers = true;
          wslConf.automount.root = "/mnt";
          defaultUser = lib.head (lib.attrNames host.users);
        };
      };
    };

  den.aspects.system.core.includes = [ den.aspects.system.core.wsl ];
}
