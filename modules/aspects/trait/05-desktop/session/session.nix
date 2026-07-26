{ den, ... }:
{
  den.aspects.desktop.session.includes = [
    den.aspects.desktop.session.compositor
    den.aspects.desktop.session.display-manager
  ];
}