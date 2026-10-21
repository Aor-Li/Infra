# macbook pro
# include 同时作用于系统侧与 home 侧，见 Enten/default.nix。
{ den, ... }:
{
  den.aspects.Magatsumi.includes = [
    den.aspects.desktop.session.compositor.aerospace
    den.aspects.app
  ];
}
