{ inputs, ... }:
{
  den.aspects.dev.ai.claude.homeManager =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      # TODO: secrets（sops）搭好后再补 provider 认证配置——
      # auth token 与 ~/.claude/settings.json（ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN）。
      home.packages = [
        inputs.llm-agents.packages.${system}.claude-code
      ];
    };
}
