{
  den.aspects.nix.home-manager = {
    # nixos / darwin 上 home-manager 作为系统模块运行，随系统 switch 一起激活。
    os = {
      # 直接用系统的 pkgs（含 allowUnfree 等 nixpkgs.config），不在 HM 里再求值一份 nixpkgs。
      home-manager.useGlobalPkgs = true;
      # 用户包装进 /etc/profiles/per-user/<user>，而不是 ~/.nix-profile。
      home-manager.useUserPackages = true;
      # 接管已有的同名文件（如从 standalone 迁过来时残留的）前先备份，而不是激活失败。
      home-manager.backupFileExtension = "hm-backup";
    };

    homeManager =
      {
        lib,
        pkgs,
        osConfig ? null,
        ...
      }:
      # 以下只对 standalone home（没有 osConfig）成立：作为系统模块时 HM 的 CLI 用不到，
      # PATH / XDG_DATA_DIRS 也由系统层负责。
      lib.mkIf (osConfig == null) {
        programs.home-manager.enable = true;

        # 非 NixOS 的 Linux（standalone home，如集群上的 Ubuntu）没有系统层把
        # ~/.nix-profile/bin 放进 PATH、把 nix 的 share 放进 XDG_DATA_DIRS。
        # genericLinux 让 HM 自己在 .profile 里 source nix.sh 补上这些。
        # darwin 由 nix-darwin 负责，且该 target 的断言只允许 Linux。
        targets.genericLinux.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isLinux;
      };
  };
}
