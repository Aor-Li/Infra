{ den, ... }:
{
  den.aspects.system.includes = [
    den.aspects.system.boot
    den.aspects.system.hardware
    den.aspects.system.platform
    den.aspects.system.power

    den.aspects.system.fonts
    den.aspects.system.locale
    den.aspects.system.tools
    den.aspects.system.xdg
  ];
}
