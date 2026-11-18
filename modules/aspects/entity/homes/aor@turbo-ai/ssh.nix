# TurboAI 的网关、开发机和节点连接；密文中的网关 ProxyCommand 使用 macOS 的 ssh-direct。
{ den, ... }:
{
  den.aspects."aor@turbo-ai".provides.ssh = den.aspects.network.ssh.provides.encryptedConfig {
    name = "TurboAI";
    sopsFile = ./ssh-secrets.yaml;
    identityFiles = {
      key = "TurboAI.pem";
      ubuntu-key = "TurboAI-ubuntu.pem";
    };
  };
}
