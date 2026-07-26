{ den, ... }:
{
  den.aspects.nix.tool.includes = [
    den.aspects.nix.nix-index
    den.aspects.nix.nh
  ];
}