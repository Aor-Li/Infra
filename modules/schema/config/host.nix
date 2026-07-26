{ den, ... }:
{
  den.schema.host.includes = with den.aspects; [
    ai
    dev
    desktop
  ];
}