{ den, ... }:
{
  den.aspects.dev.shell = {
    includes = [
      den.aspects.dev.shell.ghostty
      den.aspects.dev.shell.herdr
      den.aspects.dev.shell.starship
      den.aspects.dev.shell.tmux
    ];

    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = with pkgs; [
          bash
          fish
        ];
      };

    # nix-darwin 不会像 NixOS 那样自动把 programs.fish.enable 注册进 /etc/shells，
    # 手动加进 environment.shells 让 fish 成为合法的登录 shell（chsh 才认）。
    darwin =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.fish ];
        environment.shells = [ pkgs.fish ];
      };

    homeManager =
      { config, ... }:
      {
        programs.bash.enable = true;
        programs.fish.enable = true;
        programs.zsh.enable = true;

        # 确保一些 TUI 程序色彩显示正常（原 feature/system/shell.nix，迁 dev 时并入此处）
        home.sessionVariables.COLORTERM = "truecolor";
        systemd.user.sessionVariables.COLORTERM = "truecolor";
        
        # hack: zsh warning work around
        programs.zsh.dotDir = "${config.xdg.configHome}/zsh";
      };
  };
}
