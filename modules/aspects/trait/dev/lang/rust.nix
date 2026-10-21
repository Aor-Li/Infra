# 关掉它你会失去：rust 工具链（cargo / rustc）、rust-analyzer、rustfmt、clippy。
{ ... }:
{
  den.aspects.dev.lang.rust.homeManager =
    { config, pkgs, ... }:
    {
      home.packages = with pkgs; [
        cargo
        rustc
        rust-analyzer
        rustfmt
        clippy
      ];

      # cargo 不认 XDG；`cargo install` 的产物放 XDG data 下，bin 进 PATH。
      home.sessionVariables.CARGO_HOME = "${config.xdg.dataHome}/cargo";
      home.sessionPath = [ "${config.xdg.dataHome}/cargo/bin" ];
    };
}
