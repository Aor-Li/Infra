{ den, ... }:
{
  den.aspects.nix.nh.homeManager =
    { config, ... }:
    {
      programs.nh = {
        enable = true;
        flake = "${config.home.homeDirectory}/Infra";

        clean.enable = true;
        clean.extraArgs = "--keep-since 4d --keep 3";
      };
    };
}
