{ ... }:
{
  den.aspects.app.sunshine =
    { host, ... }:
    {
      nixos =
        { lib, ... }:
        lib.mkIf (host.graphical or false) {
          services.sunshine = {
            enable = true;
          };
        };
    };
}
