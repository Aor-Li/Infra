{ den, ... }:
{
  den.aspects.dev.editor.neovim = {

    includes = [ den.aspects.dev.editor.neovim.lazyvim ];

    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = with pkgs; [
          neovim
        ];
      };

    homeManager = {
      programs.neovim = {
        enable = true;
        # to silence warnings after version update
        withRuby = false;
        withPython3 = false;
      };
    };
  };
}
