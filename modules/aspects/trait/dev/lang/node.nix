# 关掉它你会失去：node 运行时与 npm / npx。
{
  den.aspects.dev.lang.node.homeManager =
    { config, pkgs, ... }:
    {
      home.packages = [ pkgs.nodejs ];

      # /nix/store 只读，`npm i -g` 需要一个可写的 prefix；放 XDG data 下，bin 进 PATH。
      home.sessionVariables.NPM_CONFIG_PREFIX = "${config.xdg.dataHome}/npm";
      home.sessionPath = [ "${config.xdg.dataHome}/npm/bin" ];
    };
}
