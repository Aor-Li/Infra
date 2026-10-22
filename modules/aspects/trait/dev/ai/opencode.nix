# 关掉它你会失去：OpenCode CLI 本体。
{ inputs, ... }:
{
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
