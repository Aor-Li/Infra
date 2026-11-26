# 关掉它你会失去：Google Chrome，以及指向它的 BROWSER（gh / python webbrowser / CLI 登录流程打开链接用）。
{
  den.aspects.app.browser.chrome = {
    darwin = {
      homebrew.casks = [ "google-chrome" ];
    };

    homeManager =
      { lib, pkgs, ... }:
      let
        inherit (pkgs.stdenv) hostPlatform;
        # 包一层无空格的 wrapper：不少工具把 BROWSER 当单个可执行文件而不做 shell 拆分，
        # 直接写 `open -a "Google Chrome"` 会在这些工具里失效。
        chrome-open = pkgs.writeShellScriptBin "chrome-open" ''
          exec /usr/bin/open -a "Google Chrome" "$@"
        '';
      in
      lib.mkMerge [
        # darwin 经 homebrew 安装，这里只提供 BROWSER
        (lib.mkIf hostPlatform.isDarwin {
          home.packages = [ chrome-open ];
          home.sessionVariables.BROWSER = "${chrome-open}/bin/chrome-open";
        })

        # Linux 用 nixpkgs 的 google-chrome；它只有 x86_64 构建，aarch64 主机（Kuregumo）没有 Chrome。
        (lib.mkIf (hostPlatform.isLinux && lib.meta.availableOn hostPlatform pkgs.google-chrome) {
          programs.google-chrome = {
            enable = true;
            # Chrome 默认用 text-input-v1，niri 只实现了 v3：不指定的话 fcitx5 在 Chrome 里打不出中文
            commandLineArgs = [
              "--ozone-platform-hint=auto"
              "--enable-wayland-ime"
              "--wayland-text-input-version=3"
            ];
          };
          home.sessionVariables.BROWSER = "google-chrome-stable";
        })
      ];
  };
}
