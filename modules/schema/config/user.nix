{ den, ... }:
{
  den.schema.home.includes = with den.aspects; [
    ai
    dev
    desktop
  ];
}