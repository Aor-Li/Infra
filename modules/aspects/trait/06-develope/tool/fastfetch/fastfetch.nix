{ ... }:
{
  den.aspects.dev.tool.fastfetch.homeManager =
    { config, ... }:
    let
      root = "${config.home.homeDirectory}/Infra";
    in
    {
      programs.fastfetch.enable = true;

      home.shellAliases = {
        ff = "fastfetch";
      };

      # link config（out-of-store symlink：改配置无需 rebuild 即刻生效）
      # 注意：路径写死，移动本目录时必须同步改这里。
      xdg.configFile."fastfetch/config.jsonc".source = config.lib.file.mkOutOfStoreSymlink "${root}/modules/aspects/trait/06-develope/tool/fastfetch/config.jsonc";
    };
}
