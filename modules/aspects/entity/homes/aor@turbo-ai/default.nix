# Turbo AI 集群 Ubuntu 节点上的 standalone home（den.homes."aor@turbo-ai"）。
#
# 它没有 den host，host 侧的 includes / host-aspects 到不了这里；den 会把 host 限定的
# 用户 aspect `den.aspects."aor@turbo-ai"` 叠加在 `den.aspects.aor` 之上应用，个体差异写在这。
#
# 目前只在 dgx0030 上 switch。turbo-ai 是配置名，不改系统 hostname；使用时显式传
# --flake .#aor@turbo-ai。其他节点需要不同配置时，再拆独立 home。
#
# settings 必须填在实体路径 den.homes.… 上，而不是 den.aspects."aor@turbo-ai".settings
# （那只是声明槽，见 meta/aspect-settings/_lib/lint.nix）。
{ den, lib, ... }:
{
  den.aspects."aor@turbo-ai".includes = [
    # 本机需要访问的 SSH 目标；连接配置和 PEM 随目标一起分发。
    den.aspects."aor@ali-cloud".provides.ssh
    # 常驻个人 Rex server，Mac 端经 SSH 隧道连入（见 multiplexer/rex.nix）
    den.aspects.dev.shell.multiplexer.rex
    # 集群节点 CPU / GPU 占用一览
    den.aspects.dev.ops.hwstat
  ];

  den.homes.x86_64-linux."aor@turbo-ai".settings = {
    # 服务器用途，不要 Music / Videos / Public 这些 XDG 用户目录
    system.xdg.userDirs = false;

    # 集群账号没有 chsh 权限，登录 shell 只能是 bash：交互式 bash 末尾 exec 进 fish
    dev.shell.execFish = true;

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
