{ den, ... }:
{
  den.aspects.nix.nix-index.homeManager = {
    programs.nix-index.enable = true;
  };
}
