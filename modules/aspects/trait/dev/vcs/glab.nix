# 关掉它你会失去：glab（GitLab 命令行）。
{
  den.aspects.dev.vcs.glab = {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.glab ];
      };
  };
}
