{ inputs, lib, ... }:
{
  flake-file.inputs = {
    nixos-wsl.url = "github:nix-community/nixos-wsl";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
  };

  # 只有 WSL 主机才 import nixos-wsl 模块；其它 nixos 主机连选项都不该多出来。
  # aspect 函数按 host 求值，所以这里用 optionalAttrs 而不是 module 系统的 mkIf
  # （imports 不能放进 mkIf）。`or null`：standalone home（如 aor@philo）的 host 只是
  # 合成的 { name; system }，没有 virt / distro，而这个函数在 home scope 也会被调用。
  den.aspects.system.platform.wsl =
    { host, ... }:
    {
      nixos = lib.optionalAttrs (host.virt or null == "wsl" && host.distro or null == "nixos") {
        imports = [ inputs.nixos-wsl.nixosModules.wsl ];
        wsl = {
          enable = true;
          useWindowsDriver = true;
          startMenuLaunchers = true;
          wslConf.automount.root = "/mnt";
          defaultUser = lib.head (lib.attrNames host.users);
        };
      };
    };
}
