{ den, ... }:
{
  den.aspects.network.proxy.includes = [
    den.aspects.network.proxy.clash
    den.aspects.network.proxy.ssh-direct
  ];
}
