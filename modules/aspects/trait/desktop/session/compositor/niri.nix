# 关掉它你会失去：Wayland 滚动平铺 compositor niri（系统侧会话入口 + home 侧用户配置）。
{ inputs, ... }:
{
  flake-file.inputs = {
    niri.url = "github:sodiboo/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.session.compositor.niri = {
    nixos.programs.niri.enable = true;

    homeManager =
      { pkgs, ... }:
      {
        imports = [ inputs.niri.homeModules.niri ];
        programs.niri = {
          enable = true;
          # 用 nixpkgs 的 niri，与系统侧 programs.niri 同一个包，走二进制缓存。
          # niri-flake 自带的包从源码构建、依赖钉得老（已撞上 nixpkgs 删掉的 libdisplay-info_0_2）。
          package = pkgs.niri;
        };
      };
  };
}
