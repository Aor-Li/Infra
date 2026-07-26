{ den, ... }:
{
  den.aspects.nix.home-manager.homeManager = {
    programs.home-manager.enable = true;
  };
}