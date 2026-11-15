{ den, ... }:
{
  # 开了 sshd 的 host（server 角色）上允许这些公钥以 aor 登录；sshd 禁用了密码登录，
  # 这里没有 key 就只能去 tty 了。
  den.aspects.aor.nixos.users.users.aor.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMU2Aa8TVEcmC0uDdqve6MLKh1orjoGpUtIkpphjZoVj aor@Shokuin"
  ];

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
