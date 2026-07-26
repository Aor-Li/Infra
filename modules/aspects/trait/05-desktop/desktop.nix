{ den, ... }:
{
  den.aspects.desktop.includes = [
    den.aspects.desktop.session
    den.aspects.desktop.shell
    den.aspects.desktop.input
    den.aspects.desktop.appearance
  ];
}
