{ ... }:
{
  den.aspects.dev.shell.herdr = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.herdr ];
      };
  };
}
