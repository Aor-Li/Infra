# 关掉它你会失去：第三方 skill 包。
{ inputs, lib, ... }:
{
  # 不进仓库，只当源码树用，版本由 flake.lock 钉住。
  flake-file.inputs.mattpocock-skills = {
    url = "github:mattpocock/skills";
    flake = false;
  };

  den.aspects.dev.ai.vendor.homeManager =
    let
      # 逐个挂的理由见 mine/mine.nix。
      mount =
        dir:
        lib.mapAttrs' (name: _: lib.nameValuePair ".agents/skills/${name}" { source = "${dir}/${name}"; }) (
          lib.filterAttrs (name: type: type == "directory" && builtins.pathExists "${dir}/${name}/SKILL.md") (
            builtins.readDir dir
          )
        );

      # 只取 upstream 的 plugin.json 实际发布的两组，in-progress/ deprecated/
      # misc/ 是作者的草稿区，不挂。
      mattpocock = map (group: "${inputs.mattpocock-skills}/skills/${group}") [
        "engineering"
        "productivity"
      ];
    in
    {
      home.file = lib.mkMerge (map mount mattpocock);
    };
}
