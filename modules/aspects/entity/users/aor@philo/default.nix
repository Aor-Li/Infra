# 公司集群 Ubuntu 节点上的 standalone home（den.homes."aor@philo"）。
#
# 它没有 den host，host 侧的 includes / host-aspects 到不了这里；den 会把 host 限定的
# 用户 aspect `den.aspects."aor@philo"` 叠加在 `den.aspects.aor` 之上应用，个体差异写在这。
{ den, ... }:
{
  den.aspects."aor@philo".includes = [
    # 常驻个人 Rex server，Mac 端经 SSH 隧道连入（见 multiplexer/rex.nix）
    den.aspects.dev.shell.multiplexer.rex
  ];
}
