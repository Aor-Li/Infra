# 关掉它：机器按平台默认策略自动休眠，无人值守的 server 会睡死、远程连接断开。
{ lib, ... }:
{
  den.aspects.system.power.sleep =
    { host, ... }:
    let
      # 只有 server 需要彻底不睡；desktop / laptop 保留各自平台的默认行为。
      neverSleep = host.role == "server";
    in
    {
      nixos = lib.mkIf neverSleep {
        # 禁掉四个 target 之后，任何组件都无法再发起休眠。
        systemd.targets = {
          sleep.enable = false;
          suspend.enable = false;
          hibernate.enable = false;
          hybrid-sleep.enable = false;
        };

        # 物理事件同样忽略：合盖、电源键、睡眠键、休眠键都不再触发 logind 动作。
        services.logind.settings.Login = {
          HandleLidSwitch = "ignore";
          HandleLidSwitchExternalPower = "ignore";
          HandlePowerKey = "ignore";
          HandleSuspendKey = "ignore";
          HandleHibernateKey = "ignore";
        };
      };

      # darwin 没有 systemd/logind，等价能力全在 systemsetup 一层：三档 idle sleep
      # 对应上面的 systemd.targets，allowSleepByPowerButton 对应 HandlePowerKey。
      darwin = lib.mkIf neverSleep {
        power.sleep = {
          computer = "never";
          display = "never";
          harddisk = "never";
          allowSleepByPowerButton = false;
        };
      };
    };
}
