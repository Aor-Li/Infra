{ ... }:
{
  den.aspects.dev.env.direnv.homeManager = {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
