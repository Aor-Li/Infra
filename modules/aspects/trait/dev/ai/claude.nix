# 关掉它你会失去：Claude Code CLI 本体与 Claude 桌面客户端。
{ inputs, ... }:
{
  den.aspects.dev.ai.claude.darwin = {
    homebrew.casks = [ "claude" ];
  };

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
