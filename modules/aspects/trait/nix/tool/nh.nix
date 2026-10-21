{
  den.aspects.nix.tool.nh.homeManager =
    { config, ... }:
    {
      programs.nh = {
        enable = true;
        flake = config.lib.repo.root;

        clean.enable = true;
        clean.extraArgs = "--keep-since 4d --keep 3";
      };
    };
}
