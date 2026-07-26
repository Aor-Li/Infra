{ den, lib, ... }:
let
  common.nix.settings = {
    experimental-features = lib.mkDefault [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];

    extra-substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://nix-community.cachix.org"
    ];

    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
in
{
  den.aspects.nix.settings = {
    nixos = lib.recursiveUpdate common {
      nix.settings.trusted-users = [ "@wheel" ];
      nixpkgs.config.allowUnfree = true;
    };

    darwin = lib.recursiveUpdate common {
      nix.settings.trusted-users = [ "@admin" "@wheel" ];
      nixpkgs.config.allowUnfree = true;
    };

    homeManager =
      { pkgs, ... }:
      lib.recursiveUpdate common {
        # standalone home-manager needs an explicit nix package to write nix.conf
        nix.package = pkgs.nix;
        nixpkgs.config.allowUnfreePredicate = _: true;
      };
  };
}
