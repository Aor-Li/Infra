# 关掉它你会失去：OpenCode CLI 本体与共享 prompt 的接线。
{ inputs, ... }:
{
  den.aspects.dev.ai.agent.opencode.homeManager =
    { config, pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      programs.opencode = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.opencode;
      };

      # skills 不用接线：OpenCode 会直接扫描 ~/.agents/skills。
      xdg.configFile."opencode/commands".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/prompts";
    };
}
