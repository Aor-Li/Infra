{ ... }:
{
  den.aspects.dev.shell.terminal.ghostty = {

    nixos = { pkgs, ... }: {
      environment.systemPackages = [ pkgs.ghostty ];
    };

    darwin = {
      homebrew.casks = [ "ghostty" ];
    };

    homeManager = { lib, pkgs, ... }: {
      programs.ghostty = {
        enable = true;
        package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin null;

        # shell integration
        enableBashIntegration = true;
        enableZshIntegration = true;
        enableFishIntegration = true;

        settings = {
          theme = "Catppuccin Mocha";
          font-family = [
            "CaskaydiaCove Nerd Font"
            "等距更纱黑体 SC"
          ];

          # window and tabs
          window-decoration = "auto";
          macos-titlebar-style = "tabs";

          # apply terminal info to shell integration
          shell-integration-features = "ssh-env,ssh-terminfo";
        };

      };
    };

  };
}
