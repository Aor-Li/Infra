{ lib, ... }:
{
  # use stand-alone home-manager
  den.schema.user.classes = lib.mkDefault [ ];
}