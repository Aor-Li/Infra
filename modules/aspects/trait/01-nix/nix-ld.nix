{ den, ... }:
{
  den.aspects.nix.nix-ld.nixos =
    { pkgs, ... }:
    {
      programs.nix-ld = {
        enable = true;
        package = pkgs.nix-ld;
      };
    };
}
