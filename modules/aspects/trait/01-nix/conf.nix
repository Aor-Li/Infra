{ den, lib, ... }:
let
  common.nix.settings = {
    experimental-features = lib.mkDefault [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];

    # Plain `substituters` (not `extra-substituters`) so the CN mirrors are
    # actually tried first: nixpkgs' own cache.nixos.org default is only
    # mkDefault-priority, so this list fully replaces it in the merge instead
    # of appending after it — otherwise cache.nixos.org keeps winning the
    # priority tie-break (mirrors advertise the same priority=40 it does,
    # since they mirror its nix-cache-info verbatim) purely by being first.
    # cache.nixos.org is re-added explicitly at the end as a fallback.
    substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://nix-community.cachix.org"
      "https://cache.nixos.org/"
    ];

    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
in
{
  # 不叫 `settings`：这个键被 den 保留给「aspect 自带的配置项」了，
  # 见 modules/meta/schema/conf.nix。名字取自它实际写出的 /etc/nix/nix.conf。
  den.aspects.nix.conf = {
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
