{ den, ... }:
{
  den.aspects.nix.includes = [
    den.aspects.nix.conf
    den.aspects.nix.nix-ld
    den.aspects.nix.home-manager
    den.aspects.nix.tool
  ];
}