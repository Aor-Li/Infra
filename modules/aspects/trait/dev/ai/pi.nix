# 关掉它你会失去：Pi Coding Agent CLI 本体。
{ inputs, ... }:
{
  den.aspects.dev.ai.pi.homeManager =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      programs.pi-coding-agent = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.pi;
      };
    };
}
