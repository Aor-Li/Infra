# 关掉它你会失去：终端文件管理器 yazi，以及 `y` 命令（退出时 cd 到最后浏览的目录）。
{
  den.aspects.dev.shell.util.yazi.homeManager =
    { pkgs, ... }:
    {
      programs.yazi = {
        enable = true;
        # Support for RAR extraction
        package = pkgs.yazi.override { _7zz = pkgs._7zz-rar; };

        # home-manager 自带的 shell wrapper 就是以前 scripts/y.sh 那个函数
        shellWrapperName = "y";
        enableBashIntegration = true;
        enableZshIntegration = true;
        enableFishIntegration = true;
      };
    };
}
