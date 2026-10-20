# 关掉它你会失去：macOS 上的平铺窗口管理（工作区 / 键盘焦点切换 / 窗口布局）
{ ... }:
{
  den.aspects.desktop.session.compositor.aerospace = {

    # 走 nix-darwin 的 services.aerospace 而非 home-manager 的 programs.aerospace：
    # standalone home 目前收不到 host 级 include（docs/known-issues.md 问题 1），
    # 系统层按 host 独立求值，能稳定落到每台 include 了它的 Mac。
    # launchd user agent 负责拉起，模块要求 start-at-login = false（默认即是）。
    darwin = {
      services.aerospace = {
        enable = true;

        settings = {
          enable-normalization-flatten-containers = true;
          enable-normalization-opposite-orientation-for-nested-containers = true;

          accordion-padding = 30;
          default-root-container-layout = "tiles";
          default-root-container-orientation = "auto";

          # 焦点切换到其他显示器时，鼠标跟随
          on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

          automatically-unhide-macos-hidden-apps = false;

          key-mapping.preset = "qwerty";

          gaps = {
            inner.horizontal = 8;
            inner.vertical = 8;
            outer.left = 8;
            outer.bottom = 8;
            outer.top = 8;
            outer.right = 8;
          };

          mode.main.binding = {
            # 布局
            alt-slash = "layout tiles horizontal vertical";
            alt-comma = "layout accordion horizontal vertical";
            alt-f = "fullscreen";
            alt-shift-f = "layout floating tiling";

            # 焦点 / 移动（vim 方向键）
            alt-h = "focus left";
            alt-j = "focus down";
            alt-k = "focus up";
            alt-l = "focus right";
            alt-shift-h = "move left";
            alt-shift-j = "move down";
            alt-shift-k = "move up";
            alt-shift-l = "move right";

            # 尺寸
            alt-minus = "resize smart -50";
            alt-equal = "resize smart +50";

            # 工作区
            alt-1 = "workspace 1";
            alt-2 = "workspace 2";
            alt-3 = "workspace 3";
            alt-4 = "workspace 4";
            alt-5 = "workspace 5";
            alt-6 = "workspace 6";
            alt-7 = "workspace 7";
            alt-8 = "workspace 8";
            alt-9 = "workspace 9";
            alt-shift-1 = "move-node-to-workspace 1";
            alt-shift-2 = "move-node-to-workspace 2";
            alt-shift-3 = "move-node-to-workspace 3";
            alt-shift-4 = "move-node-to-workspace 4";
            alt-shift-5 = "move-node-to-workspace 5";
            alt-shift-6 = "move-node-to-workspace 6";
            alt-shift-7 = "move-node-to-workspace 7";
            alt-shift-8 = "move-node-to-workspace 8";
            alt-shift-9 = "move-node-to-workspace 9";

            alt-tab = "workspace-back-and-forth";
            alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

            alt-shift-semicolon = "mode service";
          };

          # service 模式：低频操作，执行完自动回到 main
          mode.service.binding = {
            esc = [
              "reload-config"
              "mode main"
            ];
            r = [
              "flatten-workspace-tree"
              "mode main"
            ];
            f = [
              "layout floating tiling"
              "mode main"
            ];
            backspace = [
              "close-all-windows-but-current"
              "mode main"
            ];
            alt-shift-h = [
              "join-with left"
              "mode main"
            ];
            alt-shift-j = [
              "join-with down"
              "mode main"
            ];
            alt-shift-k = [
              "join-with up"
              "mode main"
            ];
            alt-shift-l = [
              "join-with right"
              "mode main"
            ];
          };

          # 不适合平铺的窗口默认浮动
          on-window-detected = [
            {
              "if".app-id = "com.apple.systempreferences";
              run = "layout floating";
            }
            {
              "if".app-id = "com.raycast.macos";
              run = "layout floating";
            }
          ];
        };
      };

      # 焦点窗口描边：平铺下一眼区分当前窗口（Catppuccin Mocha mauve / surface1）
      # 用直角：ghostty 是直角窗口，而 round 的圆角半径固定、无法调，对不上
      services.jankyborders = {
        enable = true;
        style = "round";
        width = 5.0;
        hidpi = true;
        active_color = "0xffcba6f7";
        inactive_color = "0xff45475a";
      };

      # AeroSpace 自己模拟工作区，依赖这两项 Mission Control 设置才能正常工作：
      # https://nikitabobko.github.io/AeroSpace/guide#a-note-on-mission-control
      system.defaults = {
        spaces.spans-displays = true; # 关闭"显示器具有单独的空间"
        dock.expose-group-apps = true; # Mission Control 按应用分组，避免窗口缩得过小
      };
    };

  };
}
