# 把 aspect 树镜像成一棵强类型的 settings 选项树。
#
# 契约：aspect 树里每个带 `settings` 的节点，都在实体的 `settings` 选项下的**同一
# 路径**上生成一个 submodule。一个节点可以同时「自己有 settings」和「有带 settings
# 的子节点」，两边的选项合并到同一个路径下。不是子 aspect 的键（den 结构键、class
# 名、quirk 键）一律跳过。
#
# 移植自 den 讨论 #622 的 Part 1 生成器
# <https://gist.github.com/sini/c67ccc0d38983e6636ba408e042e36be>。与上游的唯一
# 差异是 reshapeSettings 会识别 module 形态——上游用 removeAttrs，遇到显式写
# `{ options = …; }` 的写法会多套一层，把路径变成 `settings.<aspect>.options.<名字>`。
{ den, lib }:
let
  inherit (lib) mkOption types;

  # 哪些键**不是**子 aspect：den 的结构键（includes / provides / meta / …，
  # `settings` 由 default.nix 的 den.reservedKeys 加进这个集合）、已注册的 class 名
  # （nixos / darwin / homeManager）、以及 quirk/pipe 键。
  inherit (den.lib.aspects.fx.keyClassification) structuralKeysSet;
  classKeys = den.classes or { };
  quirkKeys = den.quirks or { };
  skipKey = k: structuralKeysSet ? ${k} || classKeys ? ${k} || quirkKeys ? ${k};

  # settings 块有两种写法：裸选项集 `{ foo = mkOption {...}; }`，或 module 形态
  # `{ options; config; imports; }`（需要计算型默认值时才用后者）。统一成后者。
  reshapeSettings =
    raw:
    let
      moduleShaped = raw ? options || raw ? config || raw ? imports;
    in
    {
      imports = raw.imports or [ ];
      config = raw.config or { };
      options = if moduleShaped then raw.options or { } else raw;
    };

  # 这个节点自己或它下面任何一层声明了 settings 吗？用来剪枝，让没有 settings 的
  # 分支不产生空 submodule。
  hasSettingsDeep =
    node:
    builtins.isAttrs node
    && (
      (node ? settings)
      || lib.any (k: !(skipKey k) && hasSettingsDeep (node.${k} or null)) (builtins.attrNames node)
    );

  nodeModule =
    node:
    let
      ownSettings =
        if node ? settings then
          reshapeSettings node.settings
        else
          {
            imports = [ ];
            config = { };
            options = { };
          };

      settingChildren = lib.filterAttrs (
        k: v: !(skipKey k) && builtins.isAttrs v && hasSettingsDeep v
      ) node;

      childOptions = lib.mapAttrs (
        name: child:
        mkOption {
          type = types.submodule (nodeModule child);
          default = { };
          description = "${name} 及其子 aspect 的 settings。";
        }
      ) settingChildren;
    in
    {
      inherit (ownSettings) imports config;
      options = ownSettings.options // childOptions;
    };
in
{
  # lint.nix 要走同一棵树、按同样的规则判断，复用这两个原语。
  inherit skipKey reshapeSettings;

  settingsType = types.submodule (nodeModule (den.aspects or { }));
}
