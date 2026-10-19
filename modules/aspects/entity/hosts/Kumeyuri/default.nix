# macbook air
{ den, ... }:
{
  den.aspects.Kumeyuri = {
    includes = [
      den.aspects.desktop.session.compositor.aerospace
      den.aspects.app
    ];
  };
}
