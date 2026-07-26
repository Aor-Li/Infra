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
      # 显式 key：aspect 带 `host` 上下文时会在多个 scope 上扇出，同一个上游
      # 模块会被 import 多次。module 系统靠 key 去重，缺了它就会报
      # "option programs.niri.enable is already declared"——且只在某个 home
      # 的配置与其他 home 产生差异时才暴露。
      homeManager.imports = lib.optionals enable [
        {
          key = "den:niri-home-module";
          imports = [ inputs.niri.homeModules.niri ];
        }
        {
          key = "den:niri-enable";
          programs.niri.enable = true;
        }
      ];
    };
}
