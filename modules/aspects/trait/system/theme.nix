# 关掉它你会失去：所有程序统一的配色与字体（stylix 按同一份 base16 方案生成 ghostty / tmux /
# starship / jankyborders / gtk … 的主题），各程序退回自己的默认外观。
#
# 和 fonts.nix 一样是终端与桌面共享的资源，所以在 system 而非 desktop。stylix 默认
# autoEnable：凡是装了且 stylix 有 target 的程序都会被接管，各 trait 里不要再手写配色；
# 某个程序不想要时用 `stylix.targets.<name>.enable = false` 在那个 trait 里关掉。
{ inputs, ... }:
let
  common =
    { pkgs, ... }:
    {
      stylix = {
        enable = true;
        polarity = "dark";
        base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

        fonts = {
          monospace = {
            package = pkgs.nerd-fonts.caskaydia-cove;
            name = "CaskaydiaCove Nerd Font";
          };
          # stylix 在 darwin 上把终端字号乘 4/3（ghostty 在 macOS 按 72 DPI 算 pt），
          # 9.75 → mac 上正好 13，和 ghostty 自己的默认值一致（取不能整除的值会让 ghostty
          # 配置里出现浮点转字符串的求值警告）。
          sizes.terminal = 9.75;
        };
      };
    };
in
{
  flake-file.inputs = {
    stylix.url = "github:nix-community/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.system.theme = {
    # 系统侧的 stylix 会把自己的 home 模块连同这里的设置一起塞进 home-manager.sharedModules
    # （homeManagerIntegration 默认 autoImport + followSystem），host 上的用户不用再写一份。
    os = common;
    nixos.imports = [ inputs.stylix.nixosModules.stylix ];
    darwin.imports = [ inputs.stylix.darwinModules.stylix ];

    # 只有 standalone home（没有 osConfig）需要自己 import stylix 的 home 模块。
    homeManager =
      {
        lib,
        osConfig ? null,
        ...
      }:
      {
        imports = lib.optionals (osConfig == null) [
          inputs.stylix.homeModules.stylix
          common
        ];

        # target 默认不看程序装没装都会写配置；rofi 的 target 还在写 HM 已改名的
        # programs.rofi.font，每次求值都报 rename 警告。没用 rofi，关掉。
        stylix.targets.rofi.enable = false;
        # hyprland 的 target 同样不看 hyprland.enable 就写 settings，顺带读 configType
        # 的默认值，stateVersion < 26.05 时每次求值都报 deprecation 警告。没用 hyprland，关掉。
        stylix.targets.hyprland.enable = false;
      };
  };
}
