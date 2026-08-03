{ ... }:
{
  den.aspects.dev.shell.terminal.ghostty = {

    nixos = 
      { pkgs, ... }:
      {
        systemPackages = [ pkgs.ghostty ];
      };

    darwin = {
      homebrew.casks = [ "ghostty" ];
    };

    homeManager =
      { lib, pkgs, ... }:
      {
        programs.ghostty = {
          enable = true;
          package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin null;
          settings = {
            theme = "Catppuccin Mocha";
            font-family = "CaskaydiaCove Nerd Font";
            shell-integration-features = "ssh-env,ssh-terminfo";
          };
        };
      };
  };
}
