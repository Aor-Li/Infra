{ den, ... }:
{
  den.aspects.network =
    { ... }:
    {
      includes = [
        den.aspects.network.ssh
        den.aspects.network.tailscale
      ];
    };
}
