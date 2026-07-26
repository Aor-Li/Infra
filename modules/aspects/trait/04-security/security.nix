{ den, ... }:
{
  den.aspects.security.includes = [
    den.aspects.security.secrets
  ];
}
