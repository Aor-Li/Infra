# 公司集群 Ubuntu 节点上的 standalone home（den.homes."aor@philo"）。
#
# 它没有 den host，host 侧的 includes / host-aspects 到不了这里；den 会把 host 限定的
# 用户 aspect `den.aspects."aor@philo"` 叠加在 `den.aspects.aor` 之上应用，个体差异写在这。
#
# 目前只在 dgx0030 上 switch，所以这份配置事实上就是「dgx0030 上的 home」。要在第二台
# 节点上 switch 且两边该有不同配置时，再拆出 `aor@<hostname>`（home-manager 不带 #名字
# 时会自动找 $USER@$(hostname)）。
#
# settings 必须填在实体路径 den.homes.… 上，而不是 den.aspects."aor@philo".settings
# （那只是声明槽，见 meta/aspect-settings/_lib/lint.nix）。
{ den, lib, ... }:
{
  den.aspects."aor@philo".includes = [
    # 常驻个人 Rex server，Mac 端经 SSH 隧道连入（见 multiplexer/rex.nix）
    den.aspects.dev.shell.multiplexer.rex
    # 集群节点 CPU / GPU 占用一览
    den.aspects.dev.ops.hwstat
  ];

  den.homes.x86_64-linux."aor@philo".settings = {
    # 服务器用途，不要 Music / Videos / Public 这些 XDG 用户目录
    system.xdg.userDirs = false;

    dev.ops.hwstat = {
      # 默认探测 dgx0001 … dgx0031
      hosts = map (i: "dgx" + lib.fixedWidthNumber 4 i) (lib.range 1 31);
      arenaRegistry = "/nfs/aor/arena/registry";
      # 个人 GPU 资源（A/B 组划分同 arena 约定）+ 借用的 C/D/E 组，其余可访问的卡在 hwstat 里算作「借用」
      groups = [
        {
          section = "个人";
          name = "A 组";
          cards = [ "dgx0019" "dgx0020" ];
        }
        {
          section = "个人";
          name = "B 组";
          cards = [ "dgx0028" "dgx0030" ];
        }
        {
          section = "个人";
          name = "辅助";
          cards = [ "dgx0026:0-1" ];
        }
        # 分配来的借用机器：仍属借用（不是个人资源），只是固定成组方便看
        {
          section = "借用";
          name = "C 组";
          cards = [ "dgx0003" "dgx0004" ];
        }
        {
          section = "借用";
          name = "D 组";
          cards = [ "dgx0015" "dgx0016" ];
        }
        {
          section = "借用";
          name = "E 组";
          cards = [ "dgx0001" "dgx0002" ];
        }
      ];
    };
  };
}
