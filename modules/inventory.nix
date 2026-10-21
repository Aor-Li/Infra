# 设备清单：声明所有 host / user / home。
#
# home 的 key 就是它的名字（den 自动拆成 userName@hostName），不用再写 name。
# fullname / email 有全局默认值（meta/schema/home.nix），只有不一样的才写。
#
# home 侧的可选面向（desktop / app）不在这里 include，也不在 den.aspects.<Host> 上
# include —— den 不会把 host 的 includes 推给 standalone home。写法见
# entity/hosts/*/default.nix 里的 den.aspects."aor@<Host>"。
{
  #####################
  ### System + Home ###
  #####################

  # main nixos pc
  den.hosts.x86_64-linux.Enten = {
    virt = "none";
    distro = "nixos";
    role = "desktop";
    users.aor = { };
  };
  den.homes.x86_64-linux."aor@Enten" = { };

  # macbook pro
  den.hosts.aarch64-darwin.Magatsumi = {
    virt = "none";
    distro = "darwin";
    role = "laptop";
    users.aor = { };
  };
  den.homes.aarch64-darwin."aor@Magatsumi" = { };

  # macbook air（公司机）
  den.hosts.aarch64-darwin.Kumeyuri = {
    virt = "none";
    distro = "darwin";
    role = "laptop";
    users.aor = { };
  };
  den.homes.aarch64-darwin."aor@Kumeyuri" = {
    fullname = "aor";
    email = "liyifeng@philoai.com";
  };

  # macbook nixos vm with desktop
  den.hosts.aarch64-linux.Kuregumo = {
    virt = "vm";
    distro = "nixos";
    role = "laptop";
    users.aor = { };
  };
  den.homes.aarch64-linux."aor@Kuregumo" = { };

  # mini-pc
  den.hosts.x86_64-linux.Tobimune = {
    virt = "none";
    distro = "nixos";
    role = "server";
    users.aor = { };
    settings.system.power.sleep.neverSleep = true;
  };
  den.homes.x86_64-linux."aor@Tobimune" = { };

  ############################################
  ### Standard Alone Home-Manager Profiles ###
  ############################################

  # 公司集群上的 Ubuntu 节点：没有对应 host，den 只合成 { name; system } 当 host 上下文
  den.homes.x86_64-linux."aor@philo" = {
    email = "liyifeng@philoai.com";
    # 服务器用途，不要 Music / Videos / Public 这些 XDG 用户目录
    settings.system.xdg.userDirs = false;
  };
}
