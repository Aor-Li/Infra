{ den, ... }:
{
  den.aspects.system =
    { ... }:
    {
      includes = [
        den.aspects.system.core
        den.aspects.system.i18n
        den.aspects.system.tools
        den.aspects.system.sleep
        den.aspects.system.fonts
        den.aspects.system.xdg
      ];
    };
}
