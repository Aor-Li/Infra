# 关掉它：机器不再有自己的引导入口，无法从磁盘启动到这份配置。
{ den, lib, ... }:
{
  den.aspects.system.boot =
    { host, ... }:
    {
      nixos = lib.mkIf (host.env != "wsl") {
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;
      };
    };
}
