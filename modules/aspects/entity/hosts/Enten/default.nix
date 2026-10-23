# nixos pc
#
# host 上的 include 一次喂两侧：trait 的 nixos class 进系统（niri 会话、fcitx5、sunshine …），
# homeManager class 经 host-aspects battery（entity/users/aor）进 home-manager.users.aor
# （niri 的用户配置、DMS、obsidian …）。
{ den, ... }:
{
  den.aspects.Enten = {
    includes = [
      den.aspects.desktop
      den.aspects.app
      den.aspects.dev.editor.vscode
      den.aspects.service.remote.sunshine
    ];

    nixos = {
      # FIXME: 临时使用的占位配置，在实机上生成 hardware-configuration 后重写
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-label/boot";
        fsType = "vfat";
      };
    };
  };
}
