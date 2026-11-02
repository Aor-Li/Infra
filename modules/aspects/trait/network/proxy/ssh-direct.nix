# 关掉它你会失去：macOS 上让 ssh 完全绕开 Clash TUN 直连的 `ssh-direct`。
#
# Clash 开 TUN（fake-ip + auto-route）时，所有 TCP 都会进 utun，切节点 / 重启内核 / 规则重载
# 都会掐断长连接。`ssh-direct` 是给 ssh 用的 ProxyCommand，让个别连接完全不经过 Clash：
#   - DNS：用 DoH 直接问国内公共 DNS，且 socket 绑在物理网卡上（curl --interface），
#     所以既不会拿到 198.18.x 的 fake-ip，也不会被 dns-hijack 截走；
#   - TCP：用 Apple 自带 nc 的 `-b <iface>`（IP_BOUND_IF）把 socket 钉在物理网卡上，
#     内核按网卡作用域路由，不看 utun 铺的 0/1、128/1 路由。
# 物理网卡取 scutil 的 PrimaryInterface（Clash TUN 不会抢它），换有线 / Wi-Fi 无需改配置。
# 解析失败时退回普通 nc（走 Clash），只在 stderr 提示，不让连接直接失败。
#
# 用法（~/.ssh/config 手写，本仓库不管理）：在需要直连的那一跳上加
#     ProxyCommand /etc/profiles/per-user/aor/bin/ssh-direct %h %p
# 写绝对路径是因为 launchd agent（如 rex 隧道）的 PATH 里没有用户 profile。
{
  den.aspects.network.proxy.ssh-direct = {
    homeManager =
      { lib, pkgs, ... }:
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        home.packages = [
          (pkgs.writeShellApplication {
            name = "ssh-direct";
            runtimeInputs = [
              pkgs.curl
              pkgs.jq
            ];
            text = ''
              if [ $# -ne 2 ]; then
                echo "usage: ssh-direct <host> <port>" >&2
                exit 2
              fi
              host=$1
              port=$2

              iface=$(printf 'show State:/Network/Global/IPv4\n' | /usr/sbin/scutil \
                | awk '/PrimaryInterface/ { print $3 }')

              if [[ $host =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
                ip=$host
              else
                ip=
                if [ -n "$iface" ]; then
                  for doh in https://223.5.5.5/resolve https://1.12.12.12/dns-query; do
                    ip=$(curl -fsS --max-time 3 --interface "$iface" \
                      -H 'accept: application/dns-json' \
                      "$doh?name=$host&type=A" 2>/dev/null \
                      | jq -r '[.Answer[]? | select(.type == 1) | .data] | first // empty') || ip=
                    [ -n "$ip" ] && break
                  done
                fi
              fi

              if [ -z "$iface" ] || [ -z "$ip" ]; then
                echo "ssh-direct: 无法直连解析 $host（iface=''${iface:-?}），退回经 Clash 连接" >&2
                exec /usr/bin/nc "$host" "$port"
              fi
              exec /usr/bin/nc -b "$iface" -G 5 "$ip" "$port"
            '';
          })
        ];
      };
  };
}
