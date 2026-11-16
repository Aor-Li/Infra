# 同事开的阿里云 ECS（Ubuntu 24.04，x86_64，美国区）上的 standalone home（den.homes."aor@ali-cloud"）。
#
# hostname 是阿里云生成的 iZ… 串，机器归同事，不去改它；所以 switch 时要写明名字：
#   home-manager switch --flake ~/Infra#aor@ali-cloud
# 从别的机器连过来：entity 里 include den.aspects.network.ssh.remote.ali-cloud。
#
# home-manager 管不到的系统层是装机时手工做的（root 执行）：
#   - useradd -m -s /bin/bash aor；~aor/.ssh/authorized_keys 放 ali-cloud.pem 的公钥
#   - nix 官方安装器 --daemon（多用户）
#   - /etc/nix/nix.conf 加 trusted-users = root aor，否则 aor 自己 nix.conf 里的
#     substituters 会被 daemon 忽略
#   - loginctl enable-linger aor，rex server（systemd user service）在 ssh 断开后继续跑
#
# gitlab.gnome.org 拒绝这台机器的 IP（HTTP 406），stylix 的 gnome-shell input 拉不下来；
# 该 input 的 rev 变了以后，在能访问的机器上 nix copy 过去：
#   nix copy --to ssh-ng://ali-cloud <inputs.stylix.inputs.gnome-shell.outPath>
{ den, ... }:
{
  den.aspects."aor@ali-cloud".includes = [
    # 常驻个人 Rex server，Mac 端经 SSH 隧道连入（见 multiplexer/rex.nix）
    den.aspects.dev.shell.multiplexer.rex
  ];

  den.homes.x86_64-linux."aor@ali-cloud".settings = {
    # 在美国，国内镜像比官方缓存慢一个数量级
    nix.conf.cnMirrors = false;
    # 服务器用途，不要 Music / Videos / Public 这些 XDG 用户目录
    system.xdg.userDirs = false;
  };
}
