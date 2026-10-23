{ den, ... }:
{
  den.aspects.network.includes = [
    den.aspects.network.proxy
    den.aspects.network.ssh
    den.aspects.network.tailscale
  ];
}
