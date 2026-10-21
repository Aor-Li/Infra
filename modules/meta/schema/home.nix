{ lib, ... }:
{
  den.schema.home.options = {
    fullname = lib.mkOption {
      type = lib.types.str;
      default = "Aor-Li";
      description = "Full name of the home's owner (used as git user.name).";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "liyifeng0039@gmail.com";
      description = "Email of the home's owner (used as git user.email).";
    };

    # 本仓库在这台机器上 checkout 到哪。null = 默认 ~/Infra（在 home-manager 侧按
    # home.homeDirectory 推导）。所有 out-of-store symlink 都经由 config.lib.repo 从这里出发，
    # 仓库换位置只改这一个值。
    repoRoot = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Absolute path of this repository's checkout on the machine; null means ~/Infra.";
    };
  };
}
