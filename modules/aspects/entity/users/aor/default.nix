{ den, ... }:
{
  den.aspects.aor.includes = [
    den.provides.primary-user

    # nix-darwin 只在 programs.fish.enable 时生成 /etc/fish/config.fish，
    # 那是 fish 拿到 nix PATH 的唯一入口（zsh/bash 走 /etc/zshenv、/etc/bashrc）。
    (den.provides.user-shell "fish")
  ];
}
