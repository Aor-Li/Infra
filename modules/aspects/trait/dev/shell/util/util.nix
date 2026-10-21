{ den, ... }:
{
  # 带 shell 集成（init hook / 函数 / keybind）的 CLI；没有集成的归 dev/tool。
  den.aspects.dev.shell.util.includes = [
    den.aspects.dev.shell.util.yazi
    den.aspects.dev.shell.util.fzf
  ];
}
