# macbook pro
{ den, ... }:
{
  den.aspects.Magatsumi = {
    includes = [
      den.aspects.desktop.session.compositor.aerospace
      den.aspects.app
    ];
  };
}
