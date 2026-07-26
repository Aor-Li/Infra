{ ... }:
{
  den.aspects.app.obsidian =
    { host, ... }:
    {
      homeManager =
        { lib, ... }:
        lib.mkIf (host.graphical or false) {
          programs.obsidian = {
            enable = true;
            defaultSettings = {
              app = {
                showLineNumber = true;
                tabSize = 2;
              };

              corePlugins = [ ];
              communityPlugins = [
                "obsidian-style-settings"
              ];
            };
          };

          # todo: currently obsidian is set in ui interface, and plugin install seems worked just fine.
        };
    };
}
