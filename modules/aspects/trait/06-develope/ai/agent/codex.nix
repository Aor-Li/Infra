# 关掉它你会失去：Codex CLI 本体与 ACP 接入。
{ inputs, ... }:
{
  den.aspects.dev.ai.agent.codex.homeManager =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      # 没有接线要做：~/.agents/skills 本来就是 Codex 的 USER scope；prompt 那边
      # 自定义命令在 0.117 被移除了，要给 Codex 用就得写成 skill。
      programs.codex = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.codex;
      };

      # ACP adapter 当前主要供 Obsidian 的 Agent 插件启动 Codex。
      home.packages = [ inputs.llm-agents.packages.${system}.codex-acp ];
    };
}
