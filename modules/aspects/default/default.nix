{ den, lib, ... }:
{
  # general defaults
  den.default = {
    nixos.system.stateVersion = lib.mkDefault "25.11";
    homeManager.home.stateVersion = lib.mkDefault "25.11";
    darwin.system.stateVersion = lib.mkDefault 6;

    includes = [
      den.aspects.nix
      den.aspects.system
      den.aspects.security
      den.aspects.network

      den.provides.define-user
      den.provides.hostname
    ];
  };
}
