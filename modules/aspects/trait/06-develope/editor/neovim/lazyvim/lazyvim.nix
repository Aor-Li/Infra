{ ... }:
{
  den.aspects.dev.editor.neovim.lazyvim.homeManager =
    { config, pkgs, ... }:
    let
      # 仓库根路径。源仓库写死为 /home/aor/infra（留有兼容 TODO），
      # 这里从 home 目录推导，与 feature/nix/nh.nix 的约定一致。
      root = "${config.home.homeDirectory}/Den-Infra";
    in
    {
      # out-of-store symlink：直接改 _lazyvim/ 下的 lua 即刻生效，无需 rebuild
      xdg.configFile."lazyvim".source = config.lib.file.mkOutOfStoreSymlink "${root}/modules/aspects/feature/dev/editors/neovim/lazyvim/_lazyvim";

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
