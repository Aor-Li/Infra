# 关掉它你会失去：niri 上的顶栏 / 通知 / launcher（DankMaterialShell）以及它托管的 niri 配置片段。
{ inputs, ... }:
{
  flake-file.inputs = {
    dms.url = "github:AvengeMedia/DankMaterialShell";
    dms.inputs.nixpkgs.follows = "nixpkgs";
  };

  # DMS 本体由下面的 home 侧安装；系统侧只开它的控件依赖的系统服务
  # （与上游 nixosModules.dank-material-shell 的默认一致，但不重复安装 dms 包）。
  den.aspects.desktop.shell.quickshell.dank.nixos =
    { lib, ... }:
    {
      services.power-profiles-daemon.enable = lib.mkDefault true; # 电源模式切换
      services.accounts-daemon.enable = lib.mkDefault true; # 用户头像 / 显示名
      services.geoclue2.enable = lib.mkDefault true; # 夜间模式按位置定日落
      services.upower.enable = lib.mkDefault true; # 电池 / 外设电量
      security.polkit.enable = lib.mkDefault true; # DMS 自带 polkit 认证弹窗
    };

  den.aspects.desktop.shell.quickshell.dank.homeManager =
    { config, ... }:
    {
      imports = [
        inputs.dms.homeModules.dank-material-shell
        inputs.dms.homeModules.niri
      ];

      programs.dank-material-shell = {
        enable = true;

        managePluginSettings = true;
        systemd.enable = false;
        niri.enableSpawn = true; # Auto-start DMS with niri, if enabled

        niri.includes = {
          enable = true;
          override = true;

          filesToInclude = [
            "alttab"
            "binds"
            "colors"
            "cursor"
            "layout"
            "outputs"
            "windowrules"
          ];
        };
      };

      # 把 dms/ 挂到 ~/.config/niri/dms，供上面的 includes 引用；链回仓库工作区，改 kdl 即刻生效
      xdg.configFile."niri/dms".source = config.lib.repo.link ./dms;
    };
}
