# 关掉它你会失去：Google Chrome，以及指向它的 BROWSER（gh / python webbrowser / CLI 登录流程打开链接用）。
{
  den.aspects.app.browser.chrome = {
    darwin = {
      homebrew.casks = [ "google-chrome" ];
    };

    # BROWSER 只跟着「真的装了 Chrome」的平台走——目前只有 darwin 经 homebrew 安装。
    # 包一层无空格的 wrapper：不少工具把 BROWSER 当单个可执行文件而不做 shell 拆分，
    # 直接写 `open -a "Google Chrome"` 会在这些工具里失效。
    homeManager =
      { lib, pkgs, ... }:
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
        let
          chrome-open = pkgs.writeShellScriptBin "chrome-open" ''
            exec /usr/bin/open -a "Google Chrome" "$@"
          '';
        in
        {
          home.packages = [ chrome-open ];
          home.sessionVariables.BROWSER = "${chrome-open}/bin/chrome-open";
        }
      );
  };
}
