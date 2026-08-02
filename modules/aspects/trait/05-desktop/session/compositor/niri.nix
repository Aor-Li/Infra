{ inputs, ... }:
{
  flake-file.inputs = {
    niri.url = "github:sodiboo/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.session.compositor.niri = {
    nixos.programs.niri.enable = true;

    # 显式 key：同一个上游模块可能被多个 home scope 各 import 一次，module 系统
    # 靠 key 去重，缺了它就会报 "option programs.niri.enable is already declared"
    # ——且只在某个 home 的配置与其他 home 产生差异时才暴露。成因见
    # docs/known-issues.md 问题 1 / 2。
    homeManager.imports = [
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
