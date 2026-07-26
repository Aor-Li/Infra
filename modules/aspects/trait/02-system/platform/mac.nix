{ den, lib, ... }:
{
  den.aspects.system.platform.mac =
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

        networking = {
          computerName = host.hostName;
          localHostName = host.hostName;
        };
      };
    };
}
