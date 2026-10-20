{ den, ... }:
{
  den.aspects.nix.home-manager.homeManager =
    { lib, pkgs, ... }:
    {
      programs.home-manager.enable = true;

      # 非 NixOS 的 Linux（standalone home，如集群上的 Ubuntu）没有系统层把
      # ~/.nix-profile/bin 放进 PATH、把 nix 的 share 放进 XDG_DATA_DIRS。
      # genericLinux 让 HM 自己在 .profile 里 source nix.sh 补上这些。NixOS 上重复
      # 一次无害；darwin 由 nix-darwin 负责，且该 target 的断言只允许 Linux。
      targets.genericLinux.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isLinux;
    };
}
