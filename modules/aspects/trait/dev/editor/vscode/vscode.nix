# 关掉它你会失去：VS Code 本体、它的扩展与 settings（含远程开发、gitlens、AI 扩展）。
#
# - 本体：nixpkgs 的 vscode，darwin 上由 HM 拷进 ~/Applications/Home Manager Apps。
# - 扩展：下面声明的由 nix 锁定版本；扩展目录保持可写，UI 里装的扩展照常可用，
#   决定留下的再补进列表。
# - settings.json：链回仓库里的 ./settings.json（out-of-store symlink），UI 和扩展
#   （如 set-window-color-name）写回的改动直接进 git。因此 profiles.default.userSettings
#   必须保持为空——一旦有值，HM 会生成只读的 settings.json 与这里的链接冲突。
# - 配色：stylix 的 vscode target 只保留生成主题扩展的部分；它的字体部分写的是
#   userSettings，关掉，字体与字号在 settings.json 里自己写。
{ inputs, ... }:
{
  flake-file.inputs = {
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.dev.editor.vscode.homeManager =
    { config, pkgs, ... }:
    let
      # 用当前 pkgs（含 allowUnfree）实例化 overlay，并按 vscode 版本过滤出兼容的扩展版本；
      # 取 -release 集合，不带 vscode-marketplace 默认会选中的 pre-release 版本
      marketplace =
        ((inputs.nix-vscode-extensions.overlays.default pkgs pkgs).forVSCodeVersion pkgs.vscode.version)
        .vscode-marketplace-release;

      userDir =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "${config.home.homeDirectory}/Library/Application Support/Code/User"
        else
          "${config.xdg.configHome}/Code/User";
    in
    {
      programs.vscode = {
        enable = true;
        profiles.default.extensions = with marketplace; [
          # 外观
          catppuccin.catppuccin-vsc-icons
          lennardv.set-window-color-name

          # 语言：LSP 本体由 dev/lang 提供，这里只装编辑器侧扩展
          jnoortheen.nix-ide
          llvm-vs-code-extensions.vscode-clangd

          # vcs / diff
          eamodio.gitlens
          scootersoftware.bcompare-vscode

          # 远程开发
          ms-vscode-remote.remote-ssh
          ms-vscode-remote.remote-ssh-edit
          ms-vscode-remote.remote-containers
          ms-vscode.remote-explorer
          ms-vscode.remote-server

          # ai
          anthropic.claude-code
          openai.chatgpt
          openai.codex-audio

          # 其他
          ms-ceintl.vscode-language-pack-zh-hans
          takeiteasy.switch-it-easy
        ];
      };

      stylix.targets.vscode.fonts.enable = false;

      home.file."${userDir}/settings.json".source = config.lib.repo.link ./settings.json;
    };
}
