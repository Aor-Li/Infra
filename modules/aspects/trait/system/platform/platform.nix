{ den, ... }:
{
  den.aspects.system.platform.includes = [
    den.aspects.system.platform.mac
    den.aspects.system.platform.wsl
  ];
}
