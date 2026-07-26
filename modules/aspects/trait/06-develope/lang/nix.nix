{ ... }:
{
  den.aspects.dev.lang.nix.homeManager =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.nil
        pkgs.nixfmt
        pkgs.statix
      ];
    };
}
