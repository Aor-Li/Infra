{ den, ... }:
{
  den.aspects.app.includes = [
    den.aspects.app.browser
    den.aspects.app.comm
    den.aspects.app.media
    den.aspects.app.imagemagick
    den.aspects.app.obsidian
    den.aspects.app.raycast
  ];
}
