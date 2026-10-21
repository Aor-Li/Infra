{ inputs, ... }:
{
  den.aspects.dev.ai.agent.claude.homeManager =
    { config, pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      programs.claude-code = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.claude-code;
      };

      # Claude 只认自己目录下的这两处，各拉一条到中立正本。
      # 副作用：Cursor 两个目录都扫，同一个 skill 会在它的列表里出现两次。
      home.file = {
        ".claude/skills".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/skills";
        ".claude/commands".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/prompts";
      };
    };
}
