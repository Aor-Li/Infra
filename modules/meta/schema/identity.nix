# 「这份 home 属于谁、仓库 checkout 在哪」。
#
# 同一组选项同时挂在 user 与 home 两种实体上：nixos / darwin 主机上的用户由 host
# 内嵌的 home-manager 模块产出（读 user），没有对应 host 的 standalone home（如
# aor@philo）读 home。HM 侧统一经由 config.lib.{owner,repo} 取值（见
# aspects/default/home.nix），trait 不用关心自己落在哪条 pipeline 里。
{ lib, ... }:
let
  options = {
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
in
{
  den.schema.user.options = options;
  den.schema.home.options = options;
}
