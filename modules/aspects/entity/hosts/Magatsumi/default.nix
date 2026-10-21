# macbook pro
# 系统侧 / home 侧两行 include 的含义见 Enten/default.nix。
{ den, ... }:
{
  den.aspects.Magatsumi.includes = [
    den.aspects.desktop.session.compositor.aerospace
    den.aspects.app
  ];

  den.aspects."aor@Magatsumi".includes = [
    den.aspects.app
  ];
}
