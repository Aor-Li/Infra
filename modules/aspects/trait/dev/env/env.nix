{ den, ... }:
{
  den.aspects.dev.env.includes = [
    den.aspects.dev.env.devenv
    den.aspects.dev.env.direnv
  ];
}
