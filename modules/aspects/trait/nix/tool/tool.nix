{ den, ... }:
{
  den.aspects.nix.tool.includes = [
    den.aspects.nix.tool.nix-index
    den.aspects.nix.tool.nh
  ];
}
