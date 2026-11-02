# macbook pro
# include 同时作用于系统侧与 home 侧，见 Enten/default.nix。
{ den, ... }:
{
  den.aspects.Magatsumi.includes = [
    den.aspects.desktop.session.compositor.aerospace
    den.aspects.app
    den.aspects.desktop.input.karabiner
    den.aspects.dev.editor.vscode
    den.aspects.dev.editor.cursor
    den.aspects.service.remote.rustdesk
    den.aspects.dev.shell.multiplexer.rex
  ];

  # Rex：经 SSH 隧道连 dgx0030 上的个人 server（aor@philo，见 multiplexer/rex.nix）。
  # Rex.app 里 Add Remote Host → http://127.0.0.1:17297。9461 是 aor 在集群上的 uid（`id -u`）。
  # 隧道走本机 ~/.ssh/config 里的 `dgx0030` 别名，需能免交互登录（BatchMode）。
  # settings 的值只能写在实体路径上（AGENTS.md 6.1），所以这里是 den.hosts 而不是 den.aspects。
  den.hosts.aarch64-darwin.Magatsumi.settings.dev.shell.multiplexer.rex.tunnels.dgx0030 = {
    localPort = 17297;
    remoteSocket = "/run/user/9461/rex/server.sock";
  };
}
