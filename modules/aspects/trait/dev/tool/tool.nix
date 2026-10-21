{ den, ... }:
{
  den.aspects.dev.tool.includes = [
    den.aspects.dev.tool.fastfetch
    den.aspects.dev.tool.hf
    den.aspects.dev.tool.fd
    den.aspects.dev.tool.monitor
  ];
}
