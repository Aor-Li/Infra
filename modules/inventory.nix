# 设备清单：声明所有 host / user / home。
#
# nixos / darwin 主机上的用户由 home-manager 模块管理（随系统 switch），不再单独声明
# den.homes；den.homes 只留给没有 den host 的机器。
# fullname / email 有全局默认值（meta/schema/identity.nix），只有不一样的才写：
# host 上的用户写在 users.<name> 里，standalone home 写在 home 上。
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
  };
}
