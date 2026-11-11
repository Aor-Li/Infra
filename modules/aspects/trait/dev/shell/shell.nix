{ den, lib, ... }:
{
  den.aspects.dev.shell = {
    settings.execFish = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        让交互式 bash 在 rc 末尾 exec 成 fish。给改不了登录 shell 的 standalone home 用
        （集群节点上的账号没有 chsh 权限）；有 den host 的机器走 users/aor 的 user-shell。
        从 fish 里手动敲 bash、`bash -c`、或设了 NO_FISH=1 时不切换。
      '';
    };

    includes = [
      den.aspects.dev.shell.prompt
      den.aspects.dev.shell.terminal
      den.aspects.dev.shell.multiplexer
      den.aspects.dev.shell.util
    ];

    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = with pkgs; [
          bash
          fish
        ];
      };

    darwin =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.fish ];
        environment.shells = [ pkgs.fish ];
      };

    homeManager =
      {
        config,
        lib,
        settings,
        ...
      }:
      {
        programs.bash.enable = true;
        programs.fish.enable = true;
        programs.zsh.enable = true;

        home.sessionVariables.COLORTERM = "truecolor";
        systemd.user.sessionVariables.COLORTERM = "truecolor";

        # hack: zsh warning work around
        programs.zsh.dotDir = "${config.xdg.configHome}/zsh";

        # 本机局部钩子：交互式 shell 最后 source 一个 nix 不管的文件（不存在就跳过）。
        # 给"只对这台机器成立、又不该进仓库"的环境用，比如集群共享的 /nfs/aor/.env.sh。
        # 不做成 settings：这类内容本来就不该进仓库，文件存不存在天然就是按机器的。
        programs.bash.initExtra = lib.mkMerge [
          (lib.mkAfter ''
            [ -r "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
          '')

          # 改不了登录 shell 时用 bash 跳板进 fish。排在 .bashrc.local 之后：
          # 那里 export 的环境（/nfs/aor/.env.sh 的 PATH 等）由 fish 继承。
          (lib.mkIf settings.dev.shell.execFish (
            lib.mkOrder 2000 ''
              if [[ -z ''${NO_FISH-} && -z ''${BASH_EXECUTION_STRING-} ]] \
                && [[ "$(ps -o comm= -p "$PPID" 2>/dev/null)" != fish ]]; then
                shopt -q login_shell && exec ${lib.getExe config.programs.fish.package} --login
                exec ${lib.getExe config.programs.fish.package}
              fi
            ''
          ))
        ];
        programs.zsh.initContent = lib.mkAfter ''
          [ -r "$HOME/.zshrc.local" ] && . "$HOME/.zshrc.local"
        '';
        programs.fish.interactiveShellInit = lib.mkAfter ''
          test -r "$HOME/.config/fish/local.fish"; and source "$HOME/.config/fish/local.fish"
        '';
      };
  };
}
