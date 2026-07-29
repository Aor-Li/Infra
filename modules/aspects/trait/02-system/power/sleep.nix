{ lib, ... }:
{
  den.aspects.system.power.sleep = {

      

      nixos = 
        { config, lib, ... }:
        {
          
        }；

      darwin = 
        { config, lib, ... }:
        {

        };
      
      
      
      
      #lib.mkIf (host.role == "server") {
      #  systemd.targets = {
      #    sleep.enable = false;
      #    suspend.enable = false;
      #    hibernate.enable = false;
      #    hybrid-sleep.enable = false;
      #  };
      #  services.logind.settings.Login = {
      #    HandleLidSwitch = "ignore";
      #    HandleLidSwitchExternalPower = "ignore";
      #    HandlePowerKey = "ignore";
      #    HandleSuspendKey = "ignore";
      #    HandleHibernateKey = "ignore";
      #  };
      #};

    };
}
