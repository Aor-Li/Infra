{ ... }:
{
  den.aspects.dev.shell.multiplexer.herdr = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.herdr ];
      };
  };
}
