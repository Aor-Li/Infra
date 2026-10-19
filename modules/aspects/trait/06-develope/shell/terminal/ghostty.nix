{ ... }:
{
  den.aspects.dev.shell.terminal.ghostty = {

    nixos = { pkgs, ... }: {
      environment.systemPackages = [ pkgs.ghostty ];
    };

    darwin = {
      homebrew.casks = [ "ghostty" ];
    };

    homeManager = { lib, pkgs, ... }: {
      programs.ghostty = {
        enable = true;
        package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin null;

        # shell integration
        enableBashIntegration = true;
        enableZshIntegration = true;
        enableFishIntegration = true;

        settings = {
          theme = "Catppuccin Mocha";
          font-family = [
            "ComicShannsMono Nerd Font"
            "CaskaydiaCove Nerd Font"
            "等距更纱黑体 SC"
          ];

          # window：去掉标题栏但保留原生边框 / 圆角 / 阴影，平铺时窗口边界清晰
          # 注意 window-decoration = "none" 在 macOS 上会连 tabs 一起禁用
          macos-titlebar-style = "hidden";
          macos-window-shadow = true;

          window-padding-x = 10;
          window-padding-y = 8;
          window-padding-balance = true;
          window-padding-color = "extend";

          # apply terminal info to shell integration
          shell-integration-features = "ssh-env,ssh-terminfo";
        };

      };
    };

  };
}
