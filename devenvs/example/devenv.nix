# 示例项目环境：复制本目录改名后按项目需要修改。
# 文档：https://devenv.sh/reference/options/
{ pkgs, ... }:
{
  packages = [ pkgs.git ];

  # languages.python.enable = true;
  # languages.rust.enable = true;

  enterShell = ''
    echo "devenv: example"
  '';
}
