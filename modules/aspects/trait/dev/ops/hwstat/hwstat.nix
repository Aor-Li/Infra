# 关掉它你会失去：hwstat 命令——并发 ssh 到一组主机，表格展示 CPU / 内存 / GPU 使用情况与占用用户。
#
# 远端只需要 bash / top / ps（以及可选的 nvidia-smi），不需要装任何东西；连不上的主机单独报告。
# 默认主机列表来自 settings，命令行参数可临时覆盖：`hwstat dgx0001 dgx0005`。
# 每张卡一行，按 settings.groups 分组展示，没被任何分组认领的卡归入「借用」；
# 自己的 GPU 任务在「任务」列显示简短名，`-T/--tasks` 列出完整命令 / 工作目录 / arena 登记；
# `-f` 只看借用组里的空闲卡，`-v` 附带 CPU 用户，`-w 5` 每 5 秒原地刷新。
{ lib, ... }:
{
  den.aspects.dev.ops.hwstat = {
    settings.hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "hwstat 不带参数时探测的主机（ssh 目标，可用 ~/.ssh/config 里的别名）。";
    };

    settings.groups = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            section = lib.mkOption {
              type = lib.types.str;
              description = "大组标题，相邻同名的分组共用一个标题。";
            };
            name = lib.mkOption {
              type = lib.types.str;
              description = "小组名。";
            };
            cards = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "组内的卡：`主机` 表示整机所有卡，`主机:0-1,3` 表示指定卡号。";
            };
          };
        }
      );
      default = [ ];
      description = "固定分组的卡，按顺序展示；其余可访问主机上的卡归入「借用」组。分组里的主机即使不在 hosts 里也会被探测。";
    };

    settings.arenaRegistry = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "arena registry 目录；设置后 `hwstat --tasks` 会把自己的任务与 arena 登记对上。";
    };

    homeManager =
      { pkgs, settings, ... }:
      {
        home.packages = [
          (pkgs.writers.writePython3Bin "hwstat" {
            # 长行是表格格式化与远端探测脚本
            flakeIgnore = [ "E501" ];
          } (
            builtins.replaceStrings
              [
                "@HOSTS@"
                "@GROUPS@"
                "@ARENA@"
              ]
              [
                (builtins.toJSON settings.dev.ops.hwstat.hosts)
                (builtins.toJSON settings.dev.ops.hwstat.groups)
                (builtins.toJSON settings.dev.ops.hwstat.arenaRegistry)
              ] (
              builtins.readFile ./hwstat.py
            )
          ))
        ];
      };
  };
}
