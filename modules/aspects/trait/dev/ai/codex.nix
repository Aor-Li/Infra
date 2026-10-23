# 关掉它你会失去：Codex CLI 本体、ACP 接入与桌面客户端。
{ inputs, ... }:
{
  # 桌面客户端用的是 chatgpt cask（ChatGPT.app，bundle id 已是 com.openai.codex）；
  # 另一个 codex-app cask 装的是独立的 Codex.app，两者别同时装。
  den.aspects.dev.ai.codex.darwin = {
    homebrew.casks = [ "chatgpt" ];
  };

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
