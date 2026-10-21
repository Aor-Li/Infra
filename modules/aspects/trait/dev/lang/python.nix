{ ... }:
{
  den.aspects.dev.lang.python.homeManager =
    { pkgs, ... }:
    let
      python = pkgs.python3.withPackages (
        ps: with ps; [
          pip
        ]
      );
    in
    {
      home.packages = [
        python
        pkgs.uv # 项目/工具级的包与解释器管理
      ];
    };
}
