# 关掉它你会失去：agent 生命周期事件上挂的那些自动动作（以及它们共用的脚本）。
{ ... }:
{
  den.aspects.dev.ai.hooks.homeManager =
    { config, ... }:
    let
      link = import ../_lib/link.nix { inherit config; };
      scripts = link "hooks/_hooks/scripts";
    in
    {
      # 三家的事件名和 JSON 结构都不一样（Codex 是 snake_case 的 pre_tool_use，
      # Cursor 是 camelCase 的 preToolUse 且要 version: 1，Claude 是 settings.json
      # 里的 PreToolUse），所以配置文件一家一份，只有脚本能共用。
      #
      # 挂的是 hooks/ 下的 scripts 子目录而不是 hooks/ 本身：两家都会往
      # hooks/state/ 里写运行时状态，整目录接管会把那些状态写进本仓库。
      home.file = {
        ".codex/hooks.json".source = link "hooks/_hooks/codex.json";
        ".codex/hooks/scripts".source = scripts;

        ".cursor/hooks.json".source = link "hooks/_hooks/cursor.json";
        ".cursor/hooks/scripts".source = scripts;

        # Claude 只挂脚本：它的 hook 接线只能写在 ~/.claude/settings.json 里，
        # 而那个文件是运行时状态，本仓库不接管（见 cli/claude.nix）。
        # 脚本先就位，接线等 settings 的所有权问题解决后再说。
        ".claude/hooks/scripts".source = scripts;
      };
    };
}
