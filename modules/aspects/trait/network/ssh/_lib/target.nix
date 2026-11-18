# 由目标 entity 的事实生成客户端连接 aspect；不读取被连接机器的系统配置。
{ den }:
{
  name,
  hostName ? null,
  user ? null,
  port ? 22,
  proxyJump ? null,
  identityFile ? null,
  configSecret ? null,
  identitySecret ? null,
  aliases ? { },
  extraOptions ? { },
}:
{
  includes = [
    den.aspects.network.ssh
    den.aspects.security.secrets
  ];

  homeManager =
    {
      config,
      lib,
      settings,
      ...
    }:
    let
      target = {
        inherit
          hostName
          user
          port
          proxyJump
          identityFile
          ;
      }
      // lib.filterAttrs (_: value: value != null) (settings.network.ssh.targets.${name} or { });
      configName = "ssh/${name}/config";
      keyName = "ssh/${name}/key";
      useConfigSecret = target.hostName == null && configSecret != null;
      useIdentitySecret = target.identityFile == null && identitySecret != null;
      keyPath = if useIdentitySecret then config.sops.secrets.${keyName}.path else target.identityFile;
      # 每个别名的专有配置在前，共用连接参数在后。OpenSSH 对标量采用首次赋值。
      blocks = aliases // {
        ${name} = lib.optionalAttrs (target.user != null) { User = target.user; };
      };
      names = builtins.attrNames blocks;
      common =
        extraOptions
        // {
          Port = target.port;
        }
        // lib.optionalAttrs (target.hostName != null) { HostName = target.hostName; }
        // lib.optionalAttrs useConfigSecret { Include = config.sops.secrets.${configName}.path; }
        // lib.optionalAttrs (keyPath != null) {
          IdentityFile = keyPath;
          IdentitiesOnly = true;
        }
        // lib.optionalAttrs (target.proxyJump != null) { ProxyJump = target.proxyJump; };
    in
    {
      sops.secrets =
        lib.optionalAttrs useConfigSecret {
          ${configName} = configSecret // {
            mode = "0400";
          };
        }
        // lib.optionalAttrs useIdentitySecret {
          ${keyName} = identitySecret // {
            mode = "0400";
          };
        };

      programs.ssh.settings =
        if builtins.length names == 1 then
          { ${name} = common // blocks.${name}; }
        else
          blocks // { ${lib.concatStringsSep " " names} = lib.hm.dag.entryAfter names common; };
    };
}
