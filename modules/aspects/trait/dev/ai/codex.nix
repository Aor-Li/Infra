# 关掉它你会失去：Codex CLI 本体与 ACP 接入。
{ inputs, ... }:
{
  den.aspects.dev.ai.codex.homeManager =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      programs.codex = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.codex;
      };

      # ACP adapter 当前主要供 Obsidian 的 Agent 插件启动 Codex。
      home.packages = [ inputs.llm-agents.packages.${system}.codex-acp ];
    };
}
