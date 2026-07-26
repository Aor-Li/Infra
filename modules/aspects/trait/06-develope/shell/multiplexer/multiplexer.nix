{ den, ... }:
{
  den.aspects.dev.shell.multiplexer.includes = [
    den.aspects.dev.shell.multiplexer.tmux
    den.aspects.dev.shell.multiplexer.herdr
  ];
}