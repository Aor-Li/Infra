# 关掉它你会失去：`ssh TurboAI`（个人开发机 dgx0030）/ `ssh TurboAI-gw`（网关）/
# `ssh TurboAI-ubuntu`，以及经网关直达任意节点的 `ssh dgx00xx`。
#
# 私钥和连接条目都放在 entity/users/aor/secrets.yaml 的 ssh.TurboAI 下：
#   key         aor 在集群上的私钥（网关与各节点通用）
#   ubuntu-key  集群发的 pem，dgx0030 上 ubuntu 账号用
#   config      Host 条目（网关地址），落到 ~/.ssh/config.d/，由 network/ssh/client 的 Include 读入
# 解密要求本机有 ~/.config/sops/age/keys.txt（见 security/secrets）。
#
# 网关一跳用 network/proxy 的 ssh-direct 绕开 Clash，所以只在 macOS 上可用。
# 节点名 dgx0001…0031 是集群内的真实主机名，不改；TurboAI 只是这边的连接名。
{
  den.aspects.network.ssh.remote.TurboAI.homeManager =
    { config, ... }:
    let
      dir = "${config.home.homeDirectory}/.ssh";
    in
    {
      sops.secrets."ssh/TurboAI/key".path = "${dir}/TurboAI.pem";
      sops.secrets."ssh/TurboAI/ubuntu-key".path = "${dir}/TurboAI-ubuntu.pem";
      sops.secrets."ssh/TurboAI/config".path = "${dir}/config.d/TurboAI";
    };
}
