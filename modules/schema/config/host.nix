{ den, ... }:
{
  den.schema.host.includes = with den.aspects; [
    dev
    desktop
  ];
}