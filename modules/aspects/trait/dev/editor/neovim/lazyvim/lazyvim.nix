{
  den.aspects.dev.editor.neovim.lazyvim.homeManager =
    { config, pkgs, ... }:
    {
      # out-of-store symlink：直接改 _lazyvim/ 下的 lua 即刻生效，无需 rebuild
      xdg.configFile."lazyvim".source = config.lib.repo.link ./_lazyvim;

      home.packages = [
        (pkgs.writeShellScriptBin "nvim-lazy" ''
          export NVIM_APPNAME=lazyvim
          exec ${pkgs.neovim}/bin/nvim "$@"
        '')

        # tools
        pkgs.ripgrep

        # lint
        pkgs.markdownlint-cli2
      ];

      home.shellAliases = {
        vi = "nvim-lazy";
        vim = "nvim-lazy";
        nvim = "nvim-lazy";
      };
    };
}
