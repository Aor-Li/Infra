{
  den,
  inputs,
  lib,
  ...
}:
{
  # nixpkgs.orca 是仅支持 Linux 的 GNOME 屏幕阅读器，不是 StablyAI Orca。
  # 桌面应用使用上游官方 Homebrew tap，版本更新仍由 nix-darwin activation 管理。
  flake-file.inputs.orca-skills = {
    url = "github:stablyai/orca";
    flake = false;
  };

  den.aspects.app.orca = {
    darwin.homebrew = {
      taps = [ "stablyai/orca" ];
      casks = [ "stablyai/orca/orca" ];
    };

    homeManager =
      { pkgs, ... }:
      {
        # 只把 Orca CLI 暴露进 Nix profile，不把整个 Homebrew prefix 加入 PATH。
        home.packages = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          (pkgs.writeShellScriptBin "orca" ''
            exec /opt/homebrew/bin/orca "$@"
          '')
        ];

        home.file = lib.listToAttrs (
          map
            (
              name:
              lib.nameValuePair ".agents/skills/${name}" {
                source = "${inputs.orca-skills}/skills/${name}";
              }
            )
            [
              "orca-cli"
              "computer-use"
              "orchestration"
            ]
        );
      };
  };
}
