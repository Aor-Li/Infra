{
  den.aspects.dev.shell.prompt.starship = {
    homeManager =
      { lib, ... }:
      {
        programs.starship = {
          enable = true;
          enableBashIntegration = true;
          enableFishIntegration = true;
          settings = lib.importTOML ./catppuccin-powerline.toml;
        };
      };
  };
}
