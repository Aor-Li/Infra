{ den, lib, ... }:
{
  # general defaults
  den.default = {
    nixos.system.stateVersion = lib.mkDefault "25.11";
    homeManager.home.stateVersion = lib.mkDefault "25.11";
    darwin.system.stateVersion = lib.mkDefault 6;

    includes = [
      # 把 host/home 上的 settings 注入成上下文参数，下面任何一个 aspect 都可能
      # 靠 `{ settings, ... }` 读它。policy 的 dispatch 在 includes 展开之前，
      # 位置无所谓，放最前只是因为它是框架层的东西。
      den.policies.settings-injection

      den.aspects.nix
      den.aspects.system
      den.aspects.security
      den.aspects.network
      den.aspects.dev

      den.provides.define-user
      den.provides.hostname
    ];
  };
}
