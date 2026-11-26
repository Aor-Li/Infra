# 关掉它你会失去：Wayland 滚动平铺 compositor niri（系统侧会话入口 + home 侧用户配置）。
{ inputs, ... }:
{
  flake-file.inputs = {
    niri.url = "github:sodiboo/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.session.compositor.niri = {
    nixos =
      { pkgs, ... }:
      {
        programs.niri.enable = true;

        # niri 自己不带 Xwayland：PATH 里有 xwayland-satellite 时按需拉起它，
        # X11 程序（Steam、部分 Java / 旧 Electron 应用）才能运行。
        environment.systemPackages = [ pkgs.xwayland-satellite ];

        # nixpkgs 的 Chromium / Electron 包装器看到它就走原生 Wayland，并打开
        # text-input 支持（否则输入法在 obsidian / vscode 里不出候选框）。
        environment.sessionVariables.NIXOS_OZONE_WL = "1";
      };

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
