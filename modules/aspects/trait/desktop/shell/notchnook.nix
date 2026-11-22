# 关掉它你会失去：macOS 刘海处的 NotchNook 灵动岛（正在播放、日历、文件托盘、通知卡片等）。
#
# Homebrew 与 nixpkgs 都没有 NotchNook，这里自己打包 Pro 版。官网的下载链接不带版本号，内容会
# 随发布变化，不能拿来锁 hash；Sparkle appcast 里每个 build 都有固定地址的 zip（旧 build 也保留），
# 所以 src 指向那里。升级：查 appcast 最新的 sparkle:version，改 build/version，hash 置空后
# switch 一次拿真实 hash 填回来。
#   appcast：https://notchnook-v2-licensing.lo-cafe-public.workers.dev/updates/v2/appcast.xml
#
# 和 vscode 一样经 home.packages 装，HM 把 .app 拷进 ~/Applications/Home Manager Apps。版本由这里管，
# 所以关掉 Sparkle 的自动检查与自动安装，否则 App 自己升级完会在下次 switch 时被换回旧版。
# 开机自启同 Mos，交给 launchd，不用 App 里的「开机启动」开关。
{
  den.aspects.desktop.shell.notchnook = {
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        appName = "NotchNook Pro.app";

        notchnook = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "notchnook-pro";
          version = "2.0.11";
          build = "2077";

          src = pkgs.fetchurl {
            url = "https://notchnook-v2-licensing.lo-cafe-public.workers.dev/updates/v2/NotchNook-Pro-build${finalAttrs.build}.zip";
            hash = "sha256-ogURDh4QrRGNV/GUnPWbwaHKwL3TDRSx2cfrtL4n3wc=";
          };

          nativeBuildInputs = [ pkgs.unzip ];
          sourceRoot = appName;
          # 开发者签名并公证过的 bundle，不能动里面的任何字节，否则签名失效
          dontFixup = true;

          installPhase = ''
            runHook preInstall
            mkdir -p "$out/Applications/${appName}"
            cp -R . "$out/Applications/${appName}"
            runHook postInstall
          '';

          meta = {
            description = "Dynamic Island for the MacBook notch";
            homepage = "https://lo.cafe/notchnook/";
            license = lib.licenses.unfree;
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = [ "aarch64-darwin" ];
          };
        });
      in
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        home.packages = [ notchnook ];

        launchd.agents.notchnook = {
          enable = true;
          config = {
            # open 对已在运行的 App 是 no-op
            ProgramArguments = [
              "/usr/bin/open"
              "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/${appName}"
            ];
            RunAtLoad = true;
          };
        };

        # 用户偏好优先于 Info.plist 里的 SUEnableAutomaticChecks = true
        targets.darwin.defaults."com.getnotchnook.NotchNookPro" = {
          SUEnableAutomaticChecks = false;
          SUAutomaticallyUpdate = false;
        };
      };
  };
}
