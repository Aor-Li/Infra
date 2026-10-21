{
  den.aspects.dev.tool.fastfetch.homeManager =
    { config, ... }:
    {
      programs.fastfetch.enable = true;

      home.shellAliases = {
        ff = "fastfetch";
      };

      # out-of-store symlink 链回仓库工作区：改配置无需 rebuild 即刻生效
      xdg.configFile."fastfetch/config.jsonc".source = config.lib.repo.link ./config.jsonc;
    };
}
