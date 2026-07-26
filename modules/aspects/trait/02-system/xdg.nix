{ ... }:
{
  den.aspects.system.xdg.homeManager =
    { ... }:
    {
      xdg = {
        enable = true;
        userDirs = {
          enable = true;
          createDirectories = true;

          # 不生成桌面、下载、文档、音乐、图片、视频等目录
          setSessionVariables = false;
        };
      };
    };
}
