{ ... }:
{
  # `os` 是 den 内置的便利 class，自动转发到 nixos 与 darwin 两边。
  den.aspects.system.tools = {
    os =
      { pkgs, ... }:
      {
        environment.systemPackages = with pkgs; [
          vim
          wget
          tree
          htop
          btop
          fd
          fzf
        ];

        environment.variables.EDITOR = "nvim";
      };
  };
}
