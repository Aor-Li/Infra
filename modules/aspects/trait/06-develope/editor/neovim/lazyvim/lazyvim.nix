{ ... }:
{
  den.aspects.dev.editor.neovim.lazyvim.homeManager =
    { config, pkgs, ... }:
    let
      root = "${config.home.homeDirectory}/Infra";
    in
    {
      # out-of-store symlink：直接改 _lazyvim/ 下的 lua 即刻生效，无需 rebuild
      # 注意：路径写死，移动本目录时必须同步改这里。
      xdg.configFile."lazyvim".source = config.lib.file.mkOutOfStoreSymlink "${root}/modules/aspects/trait/06-develope/editor/neovim/lazyvim/_lazyvim";

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
