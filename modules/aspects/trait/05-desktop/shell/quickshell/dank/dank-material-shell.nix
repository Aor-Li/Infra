{ inputs, ... }:
{
  flake-file.inputs = {
    dms.url = "github:AvengeMedia/DankMaterialShell";
    dms.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.shell.quickshell.dank =
    { host, ... }:
    {
      # imports 不能依赖 config，故用 host 上下文（求值期即确定）做静态门控，
      # 把上游 dms 模块与本地配置一起条件导入，避免在 darwin 等不支持的平台上
      # 触发上游模块的平台断言或 option 缺失。
      homeManager =
        { config, lib, ... }:
        let
          root = "${config.home.homeDirectory}/Den-Infra";

          dankModule = {
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

            # 将 dms 目录添加到 $HOME/.config/niri 下，从而能够被 include
            # 注意：路径写死，移动本目录时必须同步改这里。
            xdg.configFile."niri/dms".source = config.lib.file.mkOutOfStoreSymlink "${root}/modules/aspects/trait/05-desktop/shell/quickshell/dank/dms";
          };
        in
        {
          imports = lib.optionals (host.graphical or false) [
            inputs.dms.homeModules.dank-material-shell
            inputs.dms.homeModules.niri
            dankModule
          ];
        };
    };
}
