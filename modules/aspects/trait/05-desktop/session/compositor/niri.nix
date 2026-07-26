{ inputs, lib, ... }:
{
  flake-file.inputs = {
    niri.url = "github:sodiboo/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.session.compositor.niri =
    { host, ... }:
    let
      enable = (host.graphical or false) && ((host.distro or "nixos") != "darwin");
    in
    {
      nixos = lib.mkIf enable {
        programs.niri.enable = true;
      };

      # imports 不能被 mkIf 包裹（module 系统展开 imports 早于求值 config）。
      # 且 programs.niri 这个 option 只有在上游模块被 import 后才存在，
      # 故连配置一起放进 optionals——mkIf false 不足以避开 option 存在性检查。
      # 与 desktop/shell/quickshell/dank 的写法一致。
      homeManager.imports = lib.optionals enable [
        inputs.niri.homeModules.niri
        { programs.niri.enable = true; }
      ];
    };
}
