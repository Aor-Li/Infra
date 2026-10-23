# 关掉它你会失去：Karabiner-Elements 的键位改写（caps_lock ↔ left_command 等）。
#
# 链的是整个 ~/.config/karabiner 目录而不是 karabiner.json：Karabiner 保存时会用
# rename 原子替换文件，单文件 symlink 会被替换成普通文件。UI 里的改动因此直接进 git；
# 它自动生成的 automatic_backups/ 由同目录的 .gitignore 挡掉。
{
  den.aspects.desktop.input.karabiner = {
    darwin = {
      homebrew.casks = [ "karabiner-elements" ];
    };

    homeManager =
      { config, lib, pkgs, ... }:
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        xdg.configFile."karabiner".source = config.lib.repo.link ./config;
      };
  };
}
