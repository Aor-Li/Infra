# aspect 自带的类型化配置项（aspect-settings）。
#
# 只有单个 aspect 关心的开关不该往 host schema 上堆——它属于那个 aspect 自己。
# 这个特性让 aspect 声明自己的选项、实体填值、aspect 再读回来：
#
#   ① aspect 声明   den.aspects.system.power.sleep.settings.neverSleep = mkOption {...}
#   ② 实体填值      den.hosts.x86_64-linux.Tobimune.settings.system.power.sleep.neverSleep = true
#   ③ aspect 消费   nixos = { settings, ... }: ... settings.system.power.sleep.neverSleep
#
# ② 的路径与 ① 逐段一致，因为 _lib/tree.nix 把整棵 aspect 树按同样的路径镜像成了
# 选项树。加一个 setting 只需要改 aspect 自己，永远不用回到这个目录。
#
# 下面是这个特性的全部三个挂载点：保留字、声明侧（schema）、消费侧（policy）。
# 特性根目录参与 import-tree 自动导入；只有 `_lib/` 中的实现细节不参与。
{ den, lib, ... }:
let
  tree = import ./_lib/tree.nix { inherit den lib; };
  assertDeclarationsOnly = import ./_lib/lint.nix { inherit den lib tree; };
in
{
  den = {
    # 必须先保留：否则 tree.nix 的遍历会把 `settings` 当成子 aspect 走进去，一路
    # 钻进 mkOption 的 `type`（lib.types.* 的 functor.type 是自引用的）后栈溢出。
    # 症状是 `error: stack overflow; max-call-depth exceeded`。
    #
    # 副作用：`settings` 成了保留字，不能再有 aspect 叫这个名字（`nix.settings`
    # 因此改名成 `nix.conf`）。
    reservedKeys = [ "settings" ];

    # 声明侧。挂在 den.schema.conf 而不是 den.schema.host，因为 den 会把 conf 同时
    # import 进 host / user / home 三种实体——standalone home-manager 也就跟着有了
    # 同一棵 settings 树。
    schema.conf.options.settings = lib.mkOption {
      type = assertDeclarationsOnly tree.settingsType;
      default = { };
      description = "各 aspect 自带的类型化配置项，按 aspect 路径寻址。";
    };

    # 消费侧。把实体上的 settings 注入成 aspect 的上下文参数，aspect 写
    # `{ settings, ... }:` 就行，不用关心这次求值在 host 还是 home 的 pipeline 里，
    # 也不用写 `host.settings.<很长的路径>`。
    #
    # 取值来源（本仓库 home-manager 走 standalone，两条 pipeline 是分开的）：
    #
    #   nixosConfigurations / darwinConfigurations —— ctx 里只有 host → host.settings
    #   homeConfigurations                         —— ctx 里有 home  → home.settings
    #
    # 即「谁产出这份配置就读谁的 settings」，刻意不做级联：同一个开关系统层和 home
    # 层都要用的话，两边各写一次。`aor@philo` 这种没有对应 host 的 standalone home，
    # den 只合成 `{ name = ...; }` 当 host 上下文，它没有 settings，正好落到 home。
    policies.settings-injection =
      {
        host ? null,
        home ? null,
        ...
      }:
      [
        (den.lib.policy.resolve {
          # 两个 `or` 依次兜底；throw 是惰性的，真正有 aspect 去读 settings 时才会炸。
          settings =
            home.settings or host.settings
              or (throw "den: settings-injection 在既无 host 也无 home 的 scope 上被读取，无法解析 settings。");
        })
      ];
  };
}
