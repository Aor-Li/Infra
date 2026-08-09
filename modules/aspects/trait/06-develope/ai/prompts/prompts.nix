# 关掉它你会失去：手打 `/` 唤起的那批自定义提示词。
{ ... }:
{
  den.aspects.dev.ai.prompts.homeManager =
    { config, ... }:
    let
      link = import ../_lib/link.nix { inherit config; };
      prompts = link "prompts/_prompts";
    in
    {
      # 两家都是"目录里一个 .md 一条命令"，可以整目录挂同一份。
      #
      # Codex 不在列：自定义 prompt 在 0.117 被彻底移除（`~/.codex/prompts` 不再
      # 被扫描），官方给的替代品是 skill。要让 Codex 也能用，把它写成 skill，
      # frontmatter 加 `allow_implicit_invocation = false` 就只能显式唤起。
      home.file = {
        ".claude/commands".source = prompts;
        ".cursor/commands".source = prompts;
      };
    };
}
