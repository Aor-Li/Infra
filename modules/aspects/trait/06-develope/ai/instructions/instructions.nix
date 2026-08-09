# 关掉它你会失去：所有 agent 共用的那份全局指令。
{ ... }:
{
  den.aspects.dev.ai.instructions.homeManager =
    { config, ... }:
    let
      link = import ../_lib/link.nix { inherit config; };
      agents = link "instructions/AGENTS.md";
    in
    {
      # 两家的文件名不同，内容是同一份。
      # Cursor 没有对应位置：它的全局指令是设置里的 "User Rules"，存在应用状态里
      # 而不是文件，挂不了；`~/.cursor/rules/` 只对工作区生效。
      home.file = {
        ".claude/CLAUDE.md".source = agents;
        ".codex/AGENTS.md".source = agents;
      };
    };
}
