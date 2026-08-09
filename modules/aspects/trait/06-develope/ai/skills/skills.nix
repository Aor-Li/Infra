# 关掉它你会失去：三个 agent 共用的 skill 库——自己写的，以及 pin 在 flake 里的
# 第三方 skill 包。
{ inputs, lib, ... }:
{
  den.aspects.dev.ai.skills.homeManager =
    { config, ... }:
    let
      link = import ../_lib/link.nix { inherit config; };

      # 把一棵 skill 树摊平成 { <目录名> = <挂载源>; }。
      #
      # 必须摊平：Claude Code 的加载器只对 skills 根目录做一层 readdir，对每个
      # 条目（目录或 symlink 都行）找 <name>/SKILL.md，不递归。Codex 与 Cursor
      # 都递归，平铺对它们同样成立——所以平铺是三家的最大公约数。
      flatten =
        mkSource: dir:
        lib.mapAttrs (name: _: mkSource name) (
          lib.filterAttrs (
            name: type: type == "directory" && builtins.pathExists "${dir}/${name}/SKILL.md"
          ) (builtins.readDir dir)
        );

      # 自己写的：链回仓库，改内容即刻生效。
      # 代价是新增一个 skill 要 rebuild——上面那次 readDir 发生在求值期。
      mine = flatten (name: link "skills/_skills/${name}") ./_skills;

      # 第三方包不进仓库，走 flake input，版本由 flake.lock 钉住。
      # 只取 upstream 的 plugin.json 实际发布的两组，in-progress/ deprecated/
      # misc/ 是作者的草稿区，不挂。
      vendor =
        src: groups:
        lib.foldl' (
          acc: group: acc // flatten (name: "${src}/skills/${group}/${name}") "${src}/skills/${group}"
        ) { } groups;

      mattpocock = vendor inputs.mattpocock-skills [
        "engineering"
        "productivity"
      ];
    in
    {
      # ~/.agents/skills 是唯一的正本：它是跨 agent 的中立位置，Codex 把它列为
      # USER scope，Cursor 也在 skill 根白名单里。Claude Code 只认 ~/.claude/skills，
      # 那边挂一条指过来的 symlink（它的加载器接受 symlink 条目）。
      #
      # 已知副作用：Cursor 同时扫 .agents/skills 与 .claude/skills，同一个 skill
      # 可能在它的列表里出现两次。无解——Cursor 读所有 agent 的目录，而 Claude 和
      # Codex 的可用路径没有交集，至少要两个挂载点。
      home.file =
        lib.mapAttrs' (
          name: source: lib.nameValuePair ".agents/skills/${name}" { inherit source; }
        ) (mine // mattpocock)
        // {
          ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/skills";
        };
    };
}
