{ ... }:
{
  den.aspects.dev.shell.terminal.ghostty = {
    darwin = {
      homebrew.casks = [ "ghostty" ];
    };

    homeManager =
      { lib, pkgs, ... }:
      {
        programs.ghostty = {
          enable = true;
          # darwin 上 pkgs.ghostty 不可用（meta.platforms 只有 linux），置空只写配置不装包，
          # 由上面的 homebrew cask 负责安装；其他平台走 package 默认值 pkgs.ghostty。
          package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin null;

          settings = {
            shell-integration-features = "ssh-env,ssh-terminfo";
          };
        };
      };
  };
}
