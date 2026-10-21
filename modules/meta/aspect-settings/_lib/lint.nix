# 拦截「把值写进 aspect 的 settings 声明槽」这一类笔误。
#
# aspect 上的 `settings` 只是**声明**槽，只能放 mkOption；给实体填值要写实体路径
# （den.hosts.… / den.homes.…）。写反了的话，镜像出来的那棵子树没有任何消费者，
# 惰性求值永远不触发——不报错也不生效（实测：产物与完全不写这一行逐字节相同）。
# 所以这里对整棵 aspect 树做一次完整遍历，把静默失效换成求值期报错。
#
# 它是 settings submodule 里的一个 module，而不是包在 option type 外面的检查：
# den 由 den.hosts 推导 den.aspects，而 host 类型要读 schema.conf 的 option 声明；
# 要是构造 type 时就遍历 den.aspects，会形成
# host 类型 → settings type → den.aspects → den.hosts → host 类型 的无限递归。
# 放进 submodule 后，只在真正求值某个实体的 settings 时才遍历，那时 aspect 树已经成形。
#
# 上游 gist 只在文档里口头约定了这条规则，这个检查是本仓库自己加的。删掉它功能
# 不变，只是那类笔误会退回静默失效。
{
  den,
  lib,
  tree,
}:
let
  inherit (tree) skipKey reshapeSettings;

  # 一个 settings 块的 options 子树里，所有不是 option 的叶子。
  badLeaves =
    prefix: opts:
    if !(builtins.isAttrs opts) then
      [ prefix ]
    else
      lib.concatMap (
        name:
        let
          value = opts.${name};
          path = "${prefix}.${name}";
        in
        if lib.isOption value then
          [ ]
        else if builtins.isAttrs value then
          badLeaves path value
        else
          [ path ]
      ) (builtins.attrNames opts);

  walk =
    prefix: node:
    if !(builtins.isAttrs node) then
      [ ]
    else
      (lib.optionals (node ? settings) (
        badLeaves "${prefix}.settings" (reshapeSettings node.settings).options
      ))
      ++ lib.concatMap (k: walk "${prefix}.${k}" node.${k}) (
        builtins.filter (k: !(skipKey k)) (builtins.attrNames node)
      );

  errors = walk "den.aspects" (den.aspects or { });
in
# 检查通过时什么也不做，否则列出全部出错路径并在求值期报错。
{
  # 不能用 mkIf：module 系统下推 mkIf 时会强制求值 content，throw 就无条件触发了。
  config =
    if errors == [ ] then
      { }
    else
      throw ''
        den: aspect 的 `settings` 只能放选项**声明**（mkOption），下面这些位置写成了赋值：

        ${lib.concatMapStringsSep "\n" (p: "  ${p}") errors}

        给实体填值请写实体路径，例如：

          den.hosts.<system>.<Host>.settings.<aspect 路径> = ...;
          den.homes.<system>."<user>@<host>".settings.<aspect 路径> = ...;
      '';
}
