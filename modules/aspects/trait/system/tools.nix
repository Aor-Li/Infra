# 关掉它：没有 home-manager 时（root、救机、HM 还没接管）连编辑文件、下载东西都做不了。
# 只放救机级基础工具；日常 CLI（fd / fzf / htop …）归 dev/，由 home-manager 装。
{
  # `os` 是 den 内置的便利 class，自动转发到 nixos 与 darwin 两边。
  den.aspects.system.tools.os =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        vim
        curl
        wget
        tree
      ];

      # 系统层只保证 root / 救机场景有个能用的编辑器；用户会话里由 dev/editor 覆盖。
      environment.variables.EDITOR = "vim";
    };
}
