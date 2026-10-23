{ den, ... }:
{
  den.aspects.security.includes = [
    den.aspects.security.password
    den.aspects.security.secrets
  ];
}
