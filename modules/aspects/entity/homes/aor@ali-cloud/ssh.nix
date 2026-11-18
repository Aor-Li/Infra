# aor@ali-cloud 提供的 SSH 连接身份；由需要访问它的客户端显式 include。
{ den, ... }:
{
  den.aspects."aor@ali-cloud".provides.ssh = den.aspects.network.ssh.provides.target {
    name = "AliCloud";
    user = "aor";
    aliases.AliCloud-root.User = "root";
    configSecret = {
      sopsFile = ./ssh-secrets.yaml;
      key = "config";
    };
    identitySecret = {
      sopsFile = ./ssh-secrets.yaml;
      key = "key";
    };
    extraOptions = {
      ServerAliveInterval = 30;
      ServerAliveCountMax = 3;
    };
  };
}
