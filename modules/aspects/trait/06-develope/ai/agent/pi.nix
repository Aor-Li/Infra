# 关掉它你会失去：Pi Coding Agent CLI 本体与共享 prompt 的接线。
{ inputs, ... }:
{
  den.aspects.dev.ai.agent.pi.homeManager =
    { config, pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      programs.pi-coding-agent = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.pi;
      };

      # skills 不用接线：Pi 会直接扫描 ~/.agents/skills。
      home.file.".pi/agent/prompts".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/prompts";
    };
}
