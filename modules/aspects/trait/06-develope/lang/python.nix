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
      ];
    };
}
