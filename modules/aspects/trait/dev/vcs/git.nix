{
  den.aspects.dev.vcs.git = {
    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = with pkgs; [
          git
        ];
      };

    homeManager =
      { config, ... }:
      {
        programs.git = {
          enable = true;
          settings = {
            user.email = config.lib.owner.email;
            user.name = config.lib.owner.fullname;
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
