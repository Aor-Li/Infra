# define al hosts + users + homes
{
  #####################
  ### System + Home ###
  #####################

  # main nixos pc
  den.hosts.x86_64-linux.Enten = {
    env = "physical";
    role = "desktop";
    distro = "nixos";
    graphical = true;
    users.aor = { };
  };
  den.homes.x86_64-linux."aor@Enten" = {
    name = "aor@Enten";
    fullname = "Aor-Li";
    email = "liyifeng0039@gmail.com";
  };

  # macbook pro
  den.hosts.aarch64-darwin.Magatsumi = {
    env = "physical";
    role = "laptop";
    distro = "darwin";
    users.aor = { };
  };
  den.homes.aarch64-darwin."aor@Magatsumi" = {
    name = "aor@Magatsumi";
    fullname = "Aor-Li";
    email = "liyifeng0039@gmail.com";
  };

  # mackbook pro - nixos vm
  den.hosts.aarch64-linux.Kuregumo = {
    env = "virtual";
    role = "laptop";
    distro = "nixos";
    graphical = true;
    users.aor = { };
  };
  den.homes.aarch64-linux."aor@Kuregumo" = {
    name = "aor@Kuregumo";
    fullname = "Aor-Li";
    email = "liyifeng0039@gmail.com";
  };

  # wsl
  den.hosts.x86_64-linux.Kumeyuri = {
    env = "wsl";
    role = "desktop";
    distro = "nixos";
    graphical = true;
    users.aor = { };
  };
  den.homes.x86_64-linux."aor@Kumeyuri" = {
    name = "aor@Kumeyuri";
    fullname = "Aor-Li";
    email = "liyifeng0039@gmail.com";
  };

  # mini-pc
  den.hosts.x86_64-linux.Tobimune = {
    env = "physical";
    role = "server";
    distro = "nixos";
    graphical = true;
    users.aor = { };
  };
  den.homes.x86_64-linux."aor@Tobimune" = {
    name = "aor@Tobimune";
    fullname = "Aor-Li";
    email = "liyifeng0039@gmail.com";
  };

  ############################################
  ### Standard Alone Home-Manager Profiles ###
  ############################################
  den.homes.x86_64-linux."aor@philo" = {
    name = "aor@philo";
    fullname = "Aor-Li";
    email = "liyifeng0039@gmail.com";
  };
}
