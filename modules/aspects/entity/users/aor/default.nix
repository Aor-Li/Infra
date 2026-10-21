{ den, ... }:
{
  den.aspects.aor.includes = [
    den.provides.primary-user

    # 把所在 host 的 aspect 树（及其 includes）里的 homeManager class 投射给 aor：
    # entity/hosts 里 include 的 desktop / app 因此同时落到系统侧和 home 侧。
    den.provides.host-aspects

    # nix-darwin 只在 programs.fish.enable 时生成 /etc/fish/config.fish，
    # 那是 fish 拿到 nix PATH 的唯一入口（zsh/bash 走 /etc/zshenv、/etc/bashrc）。
    (den.provides.user-shell "fish")
  ];
}
