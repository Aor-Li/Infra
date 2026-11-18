# 将已有的多 Host 加密配置及配套身份文件封装成连接 aspect。
{ den }:
{
  name,
  sopsFile,
  identityFiles ? { },
}:
{
  includes = [
    den.aspects.network.ssh
    den.aspects.security.secrets
  ];
  homeManager =
    { config, lib, ... }:
    let
      secretName = key: "ssh/${name}/${key}";
      secret = key: {
        inherit sopsFile key;
        mode = "0400";
      };
    in
    {
      sops.secrets = {
        ${secretName "config"} = secret "config";
      }
      // lib.mapAttrs' (
        key: file:
        lib.nameValuePair (secretName key) (
          (secret key)
          // {
            path = "${config.home.homeDirectory}/.ssh/${file}";
          }
        )
      ) identityFiles;
      programs.ssh.includes = [ config.sops.secrets.${secretName "config"}.path ];
    };
}
