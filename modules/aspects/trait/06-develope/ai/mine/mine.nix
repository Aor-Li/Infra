# 关掉它你会失去：自己写的那批共享 skill 与 prompt。
# skills/ 与 prompts/ 是纯载荷目录，别往里放 .nix——import-tree 会把它当模块导入。
{ lib, ... }:
{
  den.aspects.dev.ai.mine.homeManager =
    { config, ... }:
    let
      # 一律 out-of-store：这些内容要和 agent 一起反复改，进了 store 就是只读，
      # 改一个字都得 rebuild。仓库路径只写在这一处，移动目录时只改这里。
      link =
        path:
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Infra/modules/aspects/trait/06-develope/ai/mine/${path}";

      # 一个 skill = 一个带 SKILL.md 的目录，逐个挂而不是整目录挂：正本要和
      # vendor/ 的 skill 合流在同一层，而 Claude 的加载器对 skills 根只做一层
      # readdir 找 <name>/SKILL.md，不递归。
      # 代价是新增 / 删除 skill 要 rebuild——这次 readDir 发生在求值期。
      skills =
        lib.mapAttrs'
          (name: _: lib.nameValuePair ".agents/skills/${name}" { source = link "skills/${name}"; })
          (
            lib.filterAttrs (
              name: type: type == "directory" && builtins.pathExists (./skills + "/${name}/SKILL.md")
            ) (builtins.readDir ./skills)
          );
    in
    {
      # prompts 整目录挂，新增一个 .md 不用 rebuild。
      home.file = skills // {
        ".agents/prompts".source = link "prompts";
      };
    };
}
