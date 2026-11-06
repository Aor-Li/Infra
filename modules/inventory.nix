# 设备清单：声明所有 host / user / home。
#
# nixos / darwin 主机上的用户由 home-manager 模块管理（随系统 switch），不再单独声明
# den.homes；den.homes 只留给没有 den host 的机器。
# fullname / email 有全局默认值（meta/schema/identity.nix），只有不一样的才写：
# host 上的用户写在 users.<name> 里，standalone home 写在 home 上。
{ lib, ... }:
{
  ##############################
  ### System + Home (module) ###
  ##############################

  # main nixos pc
  den.hosts.x86_64-linux.Enten = {
    virt = "none";
    distro = "nixos";
    role = "desktop";
    users.aor = { };
  };

  # macbook pro
  den.hosts.aarch64-darwin.Magatsumi = {
    virt = "none";
    distro = "darwin";
    role = "laptop";
    users.aor = { };
  };

  # macbook air（公司机）
  den.hosts.aarch64-darwin.Kumeyuri = {
    virt = "none";
    distro = "darwin";
    role = "laptop";
    users.aor = {
      fullname = "aor";
      email = "liyifeng@philoai.com";
    };
  };

  # macbook nixos vm with desktop
  den.hosts.aarch64-linux.Kuregumo = {
    virt = "vm";
    distro = "nixos";
    role = "laptop";
    users.aor = { };
  };

  # mini-pc
  den.hosts.x86_64-linux.Tobimune = {
    virt = "none";
    distro = "nixos";
    role = "server";
    users.aor = { };
    settings.system.power.sleep.neverSleep = true;
  };

  ##########################################
  ### Standalone Home-Manager Profiles   ###
  ##########################################

  # 公司集群上的 Ubuntu 节点：没有对应 host，den 只合成 { name; system } 当 host 上下文
  den.homes.x86_64-linux."aor@philo" = {
    email = "liyifeng@philoai.com";
    # 服务器用途，不要 Music / Videos / Public 这些 XDG 用户目录
    settings.system.xdg.userDirs = false;
    # hwstat 默认探测 dgx0001 … dgx0031
    settings.dev.ops.hwstat.hosts = map (i: "dgx" + lib.fixedWidthNumber 4 i) (lib.range 1 31);
    settings.dev.ops.hwstat.arenaRegistry = "/nfs/aor/arena/registry";
    # 个人 GPU 资源（A/B 组划分同 arena 约定）+ 借用的 C/D/E 组，其余可访问的卡在 hwstat 里算作「借用」
    settings.dev.ops.hwstat.groups = [
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
}
