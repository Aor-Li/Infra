{ den, lib, ... }:
{
  den.aspects.system.core.mac =
    { host, ... }:
    {
      darwin = {
        homebrew = {
          enable = true;
          onActivation = {
            autoUpdate = true;
            upgrade = true;
            cleanup = "zap";
          };
        };

        darwin.networking = {
          computerName = host.hostName;
          localHostName = host.hostName;
        };
      };
    };

  den.aspects.system.core.includes = [ den.aspects.system.core.mac ];
}
