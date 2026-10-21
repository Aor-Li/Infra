{ ... }:
{
  den.aspects.system.locale = {

    os.time.timeZone = "Asia/Shanghai";

    nixos = {
      i18n.defaultLocale = "en_US.UTF-8";
      networking.timeServers = [
        "ntp.aliyun.com" # Aliyun NTP Server
        "ntp.tencent.com" # Tencent NTP Server
      ];
    };
  };
}
