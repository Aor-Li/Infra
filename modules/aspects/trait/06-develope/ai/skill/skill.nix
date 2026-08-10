# 关掉它你会失去：各 agent 共用的 skill 库——mine/ 里自己写的，加上 pin 在 flake 里的第三方包。
# mine/ 是纯载荷目录，别往里放 .nix——import-tree 会把它当模块导入。
{ inputs, lib, ... }:
{
  # 第三方包不进仓库，只当源码树用，版本由 flake.lock 钉住。
  flake-file.inputs.mattpocock-skills = {
    url = "github:mattpocock/skills";
    flake = false;
  };

  den.aspects.dev.ai.skill.homeManager =
    { config, ... }:
    let
      # 一个 skill = 一个带 SKILL.md 的目录。逐个挂而不是整目录挂：两个来源要合流
      # 在同一层，而 Claude 的加载器对 skills 根只做一层 readdir 找 <name>/SKILL.md，
      # 不递归。代价是新增 / 删除 skill 要 rebuild——这次 readDir 发生在求值期。
      mount =
        dir: source:
        lib.mapAttrs' (name: _: lib.nameValuePair ".agents/skills/${name}" { source = source name; }) (
          lib.filterAttrs (name: type: type == "directory" && builtins.pathExists "${dir}/${name}/SKILL.md") (
            builtins.readDir dir
          )
        );

      # 自己写的：out-of-store symlink 链回仓库，改完即刻生效，不落进只读的 store。
      # 仓库路径只写在这一处，移动目录时只改这里。
      mine = mount ./mine (
        name:
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Infra/modules/aspects/trait/06-develope/ai/skill/mine/${name}"
      );

      # 第三方：只取 upstream 的 plugin.json 实际发布的两组，in-progress/ deprecated/
      # misc/ 是作者的草稿区，不挂。
      vendor =
        map
          (
            group:
            let
              dir = "${inputs.mattpocock-skills}/skills/${group}";
            in
            mount dir (name: "${dir}/${name}")
          )
          [
            "engineering"
            "productivity"
          ];
    in
    {
      # 用 mkMerge 而不是 //：重名的 skill 会直接报冲突，不会静默被覆盖。
      home.file = lib.mkMerge ([ mine ] ++ vendor);
    };
}
