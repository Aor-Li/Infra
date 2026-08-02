{ ... }:
{
  den.aspects.app.imagemagick.homeManager =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        imagemagick
      ];
    };
}
