# 关掉它你会失去：Claude Code CLI 本体。
{ inputs, ... }:
{
  den.aspects.dev.ai.claude.homeManager =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      programs.claude-code = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.claude-code;
      };
    };
}
