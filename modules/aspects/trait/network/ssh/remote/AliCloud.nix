# 关掉它你会失去：`ssh AliCloud`（aor）/ `ssh AliCloud-root` 登录同事开的阿里云机器，
# 即 standalone home aor@AliCloud 所在的那台。
#
# 私钥和连接条目都放在 entity/users/aor/secrets.yaml 的 ssh.AliCloud 下：
#   key     同事给的 pem；机器上 root 与 aor 的 authorized_keys 都是它的公钥
#   config  Host 条目（含公网 IP），落到 ~/.ssh/config.d/，由 network/ssh/client 的 Include 读入
# 解密要求本机有 ~/.config/sops/age/keys.txt（见 security/secrets）。
#
# 在 macOS 上，到这台机器的流量由 Clash 的 AliCloud 分流线单独选出口（`netsel tune` 按 ssh
# 登录实测挑选，见 network/proxy/clash.nix）。
{
  den.aspects.network.ssh.remote.AliCloud.homeManager =
    { config, ... }:
    let
      dir = "${config.home.homeDirectory}/.ssh";
    in
    {
      sops.secrets."ssh/AliCloud/key".path = "${dir}/AliCloud.pem";
      sops.secrets."ssh/AliCloud/config".path = "${dir}/config.d/AliCloud";
    };
}
