{ den, ... }:
{
  den.aspects.dev.editor.neovim = {
    includes = [ den.aspects.dev.editor.neovim.lazyvim ];

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
