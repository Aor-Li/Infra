{ den, ... }:
{
  den.aspects.dev.shell = {
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
      { config, lib, ... }:
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
        programs.bash.initExtra = lib.mkAfter ''
          [ -r "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
        '';
        programs.zsh.initContent = lib.mkAfter ''
          [ -r "$HOME/.zshrc.local" ] && . "$HOME/.zshrc.local"
        '';
        programs.fish.interactiveShellInit = lib.mkAfter ''
          test -r "$HOME/.config/fish/local.fish"; and source "$HOME/.config/fish/local.fish"
        '';
      };
  };
}
