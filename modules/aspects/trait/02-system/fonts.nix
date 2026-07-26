{ ... }:
{
  den.aspects.system.fonts = {
    os =
      { pkgs, ... }:
      {
        fonts.packages = with pkgs; [
          # en & cn
          maple-mono.NF-CN

          nerd-fonts.jetbrains-mono
          sarasa-gothic

          nerd-fonts.comic-shanns-mono
          lxgw-fusionkai

          # others
          nerd-fonts.monaspace
          nerd-fonts.caskaydia-cove
        ];
      };

    nixos =
      { lib, ... }:
      {
        fonts.enableDefaultPackages = lib.mkDefault true;
        fonts.fontconfig.enable = true;
      };
  };
}
