# nixos pc
#
# 两行 include 分别喂两条 pipeline：
#   den.aspects.Enten        → nixosConfigurations.Enten（系统侧：niri 会话、fcitx5、sunshine …）
#   den.aspects."aor@Enten"  → homeConfigurations."aor@Enten"（home 侧：niri 的用户配置、DMS、obsidian …）
# den 不把 host 的 includes 推给 standalone home，所以 home 侧必须用 user@host 这个名字写。
{ den, ... }:
{
  den.aspects.Enten = {
    includes = [
      den.aspects.desktop
      den.aspects.app
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

  den.aspects."aor@Enten".includes = [
    den.aspects.desktop
    den.aspects.app
  ];
}
