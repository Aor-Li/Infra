# 关掉它你会失去：Mos 的鼠标平滑滚动，以及与触控板分开设置的鼠标滚动方向。
#
# 开机自启交给 launchd，不用 App 里的「开机启动」开关：那个开关把当时 .app 的路径登记进
# 登录项，App 若是带 quarantine 从 ~/Downloads 直接打开的，登记的就是 Gatekeeper 每次随机
# 生成的 AppTranslocation 路径，重启后它就失效了。
#
# 偏好只声明标量项；按键绑定、per-app 规则等是 App 自己序列化的 JSON blob，仍在 GUI 里配。
# 声明的项在 GUI 里改了会在下次 switch 时被改回来，要改就改这里。
{
  den.aspects.desktop.input.mos = {
    darwin = {
      homebrew.casks = [ "mos" ];
    };

    homeManager =
      { lib, pkgs, ... }:
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        launchd.agents.mos = {
          enable = true;
          config = {
            # open 对已在运行的 App 是 no-op，所以和 App 自己的登录项重复也无害
            ProgramArguments = [ "/usr/bin/open" "-a" "/Applications/Mos.app" ];
            RunAtLoad = true;
          };
        };

        targets.darwin.defaults."com.caldis.Mos" = {
          smooth = true;
          smoothVertical = true;
          smoothHorizontal = true;
          smoothSimTrackpad = false;
          reverse = true;
          reverseVertical = true;
          reverseHorizontal = true;
          step = 33.6;
          speed = 2.7;
          duration = 4.35;
          deadZone = 1.0;
          hideStatusItem = true;
          # 版本由 homebrew 管
          updateCheckOnAppStart = false;
        };
      };
  };
}
