{ ... }:
{
  den.aspects.desktop.fcitx5 =
    { host, ... }:
    {
      nixos =
        { lib, pkgs, ... }:
        lib.mkIf (host.graphical or false) {
          i18n.inputMethod = {
            enable = true;
            type = "fcitx5";
            fcitx5 = {
              waylandFrontend = true;
              addons = with pkgs; [
                # GTK/Qt 应用输入支持
                fcitx5-gtk
                kdePackages.fcitx5-qt

                # "开箱即用"的中文拼音/双拼/码表等（更像你想要的"基础中英文能力"）
                qt6Packages.fcitx5-chinese-addons

                # 如果你偏好 Rime（可选，但很多人会用）
                fcitx5-rime
                rime-data

                # GUI 配置工具（可选）
                kdePackages.fcitx5-configtool
              ];
            };
          };
        };
    };
}
