{ den, ... }:
{
  den.aspects.dev.includes = [
    den.aspects.dev.shell
    den.aspects.dev.editor
    den.aspects.dev.lang
    den.aspects.dev.vcs
    den.aspects.dev.env
    den.aspects.dev.ai
    den.aspects.dev.tool
  ];
}
