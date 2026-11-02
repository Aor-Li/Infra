# 关掉它你会失去：Rex 的 CLI、Linux 上常驻的个人 Rex server，以及 macOS 上通往远端 Rex server 的 SSH 隧道。
#
# Rex 是 client/server 架构的终端复用器（https://www.superlogical.com/rex/docs）：
#   - macOS：Rex.app 自带本地 server，这里只装 `rex` CLI（programs.rex），不开 services.rex
#     （上游模块在 darwin 上开它会直接报错）。
#   - Linux：services.rex 以 systemd user service 跑个人 server（per-user，不需要 root），
#     socket 在 $XDG_RUNTIME_DIR/rex/server.sock。要在登出后继续运行需 `loginctl enable-linger`。
#
# 远程访问不用 Tailscale / 匿名 TCP，而是 SSH 隧道：把远端的 unix socket 转发到 Mac 的
# 127.0.0.1:<port>。sshd 以你的账号连上那个 socket，Rex 按 unix 对端 uid 认人（`rex server
# status` 显示 `uid … over unix`），所以鉴权就是 SSH 本身，远端不需要任何额外监听。
# 本机端口只绑 127.0.0.1，Mac 上的其他账号理论上能连，单用户 Mac 可以接受。
{ inputs, lib, ... }:
{
  flake-file.inputs = {
    # preview 频道：带 tag 的预发布版（stable 目前还没有发布）；flake.lock 记录的是不可变的
    # 版本 URL，升级用 `nix flake update rex`。
    rex.url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
    rex.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.dev.shell.multiplexer.rex = {

    settings.tunnels = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              sshHost = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "ssh 目标（~/.ssh/config 里的 Host 别名），默认取条目名。";
              };
              localPort = lib.mkOption {
                type = lib.types.port;
                description = "本机 127.0.0.1 上的端口；Rex.app 里 Add Remote Host 填 http://127.0.0.1:<port>。";
              };
              remoteSocket = lib.mkOption {
                type = lib.types.str;
                description = "远端个人 server 的 socket，即 /run/user/<远端 uid>/rex/server.sock。";
              };
            };
          }
        )
      );
      default = { };
      description = ''
        macOS 上常驻的 SSH 隧道（launchd user agent），每条把一个远端 Rex server 暴露在本机端口。
        只在 darwin 上生效；Linux 端只需要开 server。
      '';
    };

    homeManager =
      {
        lib,
        pkgs,
        settings,
        ...
      }:
      let
        inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
        tunnels = settings.dev.shell.multiplexer.rex.tunnels;
      in
      {
        imports = [ inputs.rex.homeManagerModules.default ];

        programs.rex = {
          enable = true;
          # ssh guard 依赖 programs.ssh 接管 ~/.ssh/config，而本仓库目前不管理 ssh 客户端配置
          # （各机器 ~/.ssh/config 手写）。关掉以免警告；需要时在该机器上跑一次
          # `rex terminfo setup`，它会把 guard 加进手写的 ~/.ssh/config。
          # terminfo 照常写进 ~/.terminfo，所以 ssh 进装了本 aspect 的机器时 xterm-rex 可用。
          sshGuard = false;
        };

        services.rex.enable = isLinux;

        launchd.agents = lib.mkIf isDarwin (
          lib.mapAttrs' (
            name: t:
            lib.nameValuePair "rex-tunnel-${name}" {
              enable = true;
              config = {
                ProgramArguments = [
                  "/usr/bin/ssh"
                  "-N"
                  "-o"
                  "BatchMode=yes"
                  "-o"
                  "ExitOnForwardFailure=yes"
                  "-o"
                  "ServerAliveInterval=30"
                  "-o"
                  "ServerAliveCountMax=3"
                  # 远端 server 重启后 socket 会重建，转发每次连接时才打开它，所以无需重连隧道
                  "-L"
                  "127.0.0.1:${toString t.localPort}:${t.remoteSocket}"
                  t.sshHost
                ];
                RunAtLoad = true;
                # 断网 / 远端重启后由 launchd 拉起；ThrottleInterval 防止离线时空转
                KeepAlive = true;
                ThrottleInterval = 30;
                ProcessType = "Background";
                StandardErrorPath = "/tmp/rex-tunnel-${name}.log";
              };
            }
          ) tunnels
        );
      };
  };
}
