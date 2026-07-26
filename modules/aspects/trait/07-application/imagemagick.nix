{ ... }:
{
  den.aspects.app.imagemagick =
    { host, ... }:
    {
      homeManager =
        { lib, pkgs, ... }:
        lib.mkIf (host.graphical or false) {
          home.packages = with pkgs; [
            imagemagick
          ];
        };
    };
}
