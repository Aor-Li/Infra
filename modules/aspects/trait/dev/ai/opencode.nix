# 关掉它你会失去：OpenCode CLI 本体与桌面客户端。
{ inputs, ... }:
{
  den.aspects.dev.ai.opencode.darwin = {
    homebrew.casks = [ "opencode-desktop" ];
  };

  den.aspects.dev.ai.opencode.homeManager =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      programs.opencode = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.opencode;
      };
    };
}
