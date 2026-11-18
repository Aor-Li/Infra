# TurboAI 的网关、开发机和节点连接。
#
# 网关一跳在 macOS 上经 network/proxy 的 ssh-direct 绕开 Clash TUN（切节点不掐断长连接），
# 其余平台（如 aor@ali-cloud）直连。ProxyCommand 只在这里按平台追加，密文的网关块里不写
# ProxyCommand / ProxyJump：OpenSSH 两者先出现的生效，密文又先于这里被 Include，写了就盖不掉。
{ den, ... }:
{
  den.aspects."aor@turbo-ai".provides.ssh = {
    includes = [
      (den.aspects.network.ssh.provides.encryptedConfig {
        name = "TurboAI";
        sopsFile = ./ssh-secrets.yaml;
        identityFiles = {
          key = "TurboAI.pem";
          ubuntu-key = "TurboAI-ubuntu.pem";
        };
      })
    ];
    homeManager =
      { lib, pkgs, ... }:
      {
        # 绝对路径同 ssh-direct.nix 的说明：launchd agent（rex 隧道）的 PATH 里没有用户 profile
        programs.ssh.settings."TurboAI-gw" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          ProxyCommand = "/etc/profiles/per-user/aor/bin/ssh-direct %h %p";
        };
      };
  };
}
