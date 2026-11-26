# 关掉它你会失去：开机后的图形登录界面（greetd + DMS greeter），只能在 tty 登录后手动执行 `niri-session`。
{ lib, ... }:
{
  # 静态 attrset，host 在 class 层要（见 system/platform/mac.nix 的说明）。
  den.aspects.desktop.session.display-manager.nixos =
    { config, host, ... }:
    {
      # nixpkgs 自带的 DMS greeter：跑在 niri 里的 quickshell 登录界面，经 greetd 拉起会话。
      services.displayManager.dux-greeter = {
        enable = true;
        compositor.name = "niri";
        # 每次启动 greetd 前从主用户目录复制 DMS 的设置 / 壁纸 / 配色，登录界面与桌面同一套外观
        configHome = config.users.users.${lib.head (lib.attrNames host.users)}.home;
      };

      # 登录时用同一个密码解锁 gnome-keyring（niri 会话的 Secret portal），
      # 浏览器等程序不会再单独弹出解锁密钥环的窗口
      security.pam.services.greetd.enableGnomeKeyring = true;
    };
}
