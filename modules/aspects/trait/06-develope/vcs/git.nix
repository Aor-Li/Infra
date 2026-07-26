{ ... }:
{
  den.aspects.dev.git =
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
      };
    };
}
