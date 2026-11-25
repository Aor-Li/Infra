{ den, ... }:
{
  den.aspects.network.includes = [
    den.aspects.network.core
    den.aspects.network.proxy
    den.aspects.network.ssh
  ];
}
