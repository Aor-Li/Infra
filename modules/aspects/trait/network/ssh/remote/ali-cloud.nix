# 关掉它你会失去：`ssh ali-cloud`（aor）/ `ssh ali-cloud-root` 登录同事开的阿里云机器，
# 即 standalone home aor@ali-cloud 所在的那台。
#
# 私钥和连接条目都放在 entity/users/aor/secrets.yaml 的 ssh.ali-cloud 下：
#   key     同事给的 pem；机器上 root 与 aor 的 authorized_keys 都是它的公钥
#   config  Host 条目（含公网 IP），落到 ~/.ssh/config.d/，由 network/ssh/client 的 Include 读入
# 解密要求本机有 ~/.config/sops/age/keys.txt（见 security/secrets）。
{
  den.aspects.network.ssh.remote.ali-cloud.homeManager =
    { config, ... }:
    let
      dir = "${config.home.homeDirectory}/.ssh";
    in
    {
      sops.secrets."ssh/ali-cloud/key".path = "${dir}/ali-cloud.pem";
      sops.secrets."ssh/ali-cloud/config".path = "${dir}/config.d/ali-cloud";
    };
}
