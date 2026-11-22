# macbook air
# include 同时作用于系统侧与 home 侧，见 Enten/default.nix。
{ den, ... }:
{
  den.aspects.Kumeyuri.includes = [
    den.aspects.desktop.session.compositor.aerospace
    den.aspects.app
    den.aspects.desktop.input.karabiner
    den.aspects.desktop.input.mos
    den.aspects.desktop.shell.notchnook
    den.aspects.dev.editor.vscode
    den.aspects.dev.editor.cursor
    den.aspects.service.remote.rustdesk
    den.aspects."aor@turbo-ai".provides.ssh
    den.aspects."aor@ali-cloud".provides.ssh
    den.aspects.dev.shell.multiplexer.rex
  ];

  # Rex：经 SSH 隧道连远端的个人 server（见 multiplexer/rex.nix），Rex.app 里 Add Remote Host 填
  # http://127.0.0.1:<localPort>。隧道走 ~/.ssh/config 里与条目同名的别名（对应 entity 的 provides.ssh），
  # 需能免交互登录（BatchMode）。remoteSocket 里的数字是 aor 在那台机器上的 uid（`id -u`）。
  # settings 的值只能写在实体路径上（AGENTS.md 6.1），所以这里是 den.hosts 而不是 den.aspects。
  den.hosts.aarch64-darwin.Kumeyuri.settings.dev.shell.multiplexer.rex.tunnels = {
    # TurboAI 集群 dgx0030 上的 aor@turbo-ai
    TurboAI = {
      localPort = 17297;
      remoteSocket = "/run/user/9461/rex/server.sock";
    };
    # aor@ali-cloud
    AliCloud = {
      localPort = 17298;
      remoteSocket = "/run/user/1000/rex/server.sock";
    };
  };
}
