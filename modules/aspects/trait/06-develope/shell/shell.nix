{ den, ... }:
{
  den.aspects.dev.shell = {
    includes = [
      den.aspects.dev.shell.prompt
      den.aspects.dev.shell.terminal
      den.aspects.dev.shell.multiplexer
      den.aspects.dev.shell.util
    ];

    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = with pkgs; [
          bash
          fish
        ];
      };

    darwin =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.fish ];
        environment.shells = [ pkgs.fish ];
      };

    homeManager =
      { config, ... }:
      {
        programs.bash.enable = true;
        programs.fish.enable = true;
        programs.zsh.enable = true;

        home.sessionVariables.COLORTERM = "truecolor";
        systemd.user.sessionVariables.COLORTERM = "truecolor";
        
        # hack: zsh warning work around
        programs.zsh.dotDir = "${config.xdg.configHome}/zsh";
      };
  };
}
