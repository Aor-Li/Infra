# 关掉它你会失去：hwstat 命令——并发 ssh 到一组主机，表格展示 CPU / 内存 / GPU 使用情况与占用用户。
#
# 远端只需要 bash / top / ps（以及可选的 nvidia-smi），不需要装任何东西；连不上的主机单独报告。
# 默认主机列表来自 settings，命令行参数可临时覆盖：`hwstat dgx0001 dgx0005`。
{ lib, ... }:
{
  den.aspects.dev.ops.hwstat = {
    settings.hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "hwstat 不带参数时探测的主机（ssh 目标，可用 ~/.ssh/config 里的别名）。";
    };

    homeManager =
      { pkgs, settings, ... }:
      {
        home.packages = [
          (pkgs.writers.writePython3Bin "hwstat" {
            # 长行是表格格式化与远端探测脚本
            flakeIgnore = [ "E501" ];
          } (
            builtins.replaceStrings [ "@HOSTS@" ] [ (builtins.toJSON settings.dev.ops.hwstat.hosts) ] (
              builtins.readFile ./hwstat.py
            )
          ))
        ];
      };
  };
}
