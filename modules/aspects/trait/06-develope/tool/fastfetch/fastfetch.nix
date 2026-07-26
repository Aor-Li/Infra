{ ... }:
{
  den.aspects.dev.tool.fastfetch.homeManager =
    { config, ... }:
    let
      # 仓库根路径。源仓库写死为 /home/aor/infra（留有兼容 TODO），
      # 这里从 home 目录推导，与 feature/nix/nh.nix 的约定一致。
      root = "${config.home.homeDirectory}/Den-Infra";
    in
    {
      programs.fastfetch.enable = true;

      home.shellAliases = {
        ff = "fastfetch";
      };

      # link config（out-of-store symlink：改配置无需 rebuild 即刻生效）
      xdg.configFile."fastfetch/config.jsonc".source = config.lib.file.mkOutOfStoreSymlink "${root}/modules/aspects/feature/dev/tools/fastfetch/config.jsonc";
    };
}
