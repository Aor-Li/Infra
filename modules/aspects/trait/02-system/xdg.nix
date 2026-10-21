{ lib, ... }:
{
  den.aspects.system.xdg = {

    settings = {
      userDirs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          由 home-manager 接管 XDG 用户目录：生成 ~/.config/user-dirs.dirs 并在激活时
          创建 Desktop / Documents / Downloads / Music / Pictures / Public / Templates /
          Videos。默认开启；纯服务器用途的 home（如 aor@philo）用不到这些目录，关掉。
        '';
      };
    };

    homeManager =
      { settings, ... }:
      {
        xdg = {
          enable = true;
          userDirs = {
            enable = settings.system.xdg.userDirs;
            createDirectories = settings.system.xdg.userDirs;

            # 不往 shell 环境里导出 XDG_*_DIR 变量（它只控制变量，不控制目录创建）
            setSessionVariables = false;
          };
        };
      };
  };
}
