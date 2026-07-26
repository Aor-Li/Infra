{ inputs, lib, ... }:
{
  flake-file.inputs = {
    niri.url = "github:sodiboo/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.session.compositor.niri =
    { host, ... }:
    {
      nixos = lib.mkIf (host.graphical or false) {
        programs.niri.enable = true;
      };

      homeManager = lib.mkIf (host.graphical or false) {
        imports = [
          inputs.niri.homeModules.niri
        ];
          
        programs.niri = lib.mkIf (host.distro != "darwin") {
          enable = true;
        }
      };
    };
}
