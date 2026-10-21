# 关掉它你会失去：niri 上的顶栏 / 通知 / launcher（DankMaterialShell）以及它托管的 niri 配置片段。
{ inputs, ... }:
{
  flake-file.inputs = {
    dms.url = "github:AvengeMedia/DankMaterialShell";
    dms.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.shell.quickshell.dank.homeManager =
    { config, ... }:
    {
      imports = [
        inputs.dms.homeModules.dank-material-shell
        inputs.dms.homeModules.niri
      ];

      programs.dank-material-shell = {
        enable = true;

        managePluginSettings = true;
        systemd.enable = false;
        niri.enableSpawn = true; # Auto-start DMS with niri, if enabled

        niri.includes = {
          enable = true;
          override = true;

          filesToInclude = [
            "alttab"
            "binds"
            "colors"
            "cursor"
            "layout"
            "outputs"
            "windowrules"
          ];
        };
      };

      # 把 dms/ 挂到 ~/.config/niri/dms，供上面的 includes 引用；链回仓库工作区，改 kdl 即刻生效
      xdg.configFile."niri/dms".source = config.lib.repo.link ./dms;
    };
}
