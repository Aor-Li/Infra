{ ... }:
{
  den.aspects.dev.vcs.git =
    { home, ... }:
    {
      nixos =
        { pkgs, ... }:
        {
          environment.systemPackages = with pkgs; [
            git
          ];
        };

      homeManager = {
        programs.git = {
          enable = true;
          settings = {
            user.email = home.email;
            user.name = home.fullname;
            # http.sslVerify = false;
            # https.sslVerify = false;
          };
        };
        programs.lazygit.enable = true;

        # delta 接管 git 的 diff / log / show / blame 分页与交互暂存的 diff filter。
        programs.delta = {
          enable = true;
          enableGitIntegration = true;
        };
      };
    };
}
