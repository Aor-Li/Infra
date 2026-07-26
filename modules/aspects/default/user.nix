{ den, ... }:
{
  den.schema.home.includes = with den.aspects; [
    dev
    desktop
  ];
}
