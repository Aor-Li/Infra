{ ... }:
{
  den.aspects.dev.vcs.gh = {
    homeManager = {pkgs, ... }: {
      home.packages = [ pkgs.gh ];
    };
  };
}
