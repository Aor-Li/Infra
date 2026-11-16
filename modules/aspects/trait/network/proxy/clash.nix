# 关掉它你会失去：Clash Verge 代理客户端，以及按 DGX / 国内 / 国外分流、在终端里看状态和切节点的 `netsel`。
#
# 订阅清单（有哪些订阅、顺序、哪份是汇总订阅）是所有机器共享的事实，放在 sops：
# entity/users/aor/secrets.yaml 的 clash.subscriptions，一个 YAML 列表字符串
#   - name: Forest            # 分组名；provider 名取小写
#     url: https://…          # 订阅链接带 token，所以加密
#   - name: JMS
#     url: https://…
#     summary: true           # 恰好一项：全局脚本只在这份订阅激活时改写
# 顺序即「自动容灾」的优先级。改订阅只改这里，各机器 switch 后一致。
#
# Clash Verge 一次只激活一份订阅。全局扩展脚本只在汇总订阅激活时启用 netsel 分流；
# 选其他订阅时保留其原生节点和分组，供现有节点故障时救急。clash-script.js 用
# proxy-providers 同时拉取清单里的所有订阅，再按 DGX / 国内 / 国外 / AI 分组。
# `netsel setup` 把清单套进模板写到 Verge 的 profiles/Script.js；清单里有、Verge 里还没有的
# 订阅经 clash://install-config deep link 交给 Verge 导入（profiles.yaml 归 Verge 写，这里不碰）。
#
# Verge 自己的配置（clash-verge.yaml / verge.yaml）只收敛 netsel 依赖的几项：外部控制器只听
# 127.0.0.1，secret 若是默认值就换成随机值。secret 是本机凭据、不需要跨机器一致，所以不进 sops：
# 生成一次后 Verge 自己保存，netsel 每次从 clash-verge.yaml 读，仓库里不出现它的值。
{
  den.aspects.network.proxy.clash = {
    darwin = {
      homebrew.casks = [ "clash-verge-rev" ];
    };

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        subscriptions = config.sops.secrets."clash/subscriptions".path;
        netsel =
          pkgs.writers.writePython3Bin "netsel"
            {
              libraries = [ pkgs.python3Packages.pyyaml ];
              makeWrapperArgs = [
                "--prefix"
                "PATH"
                ":"
                (lib.makeBinPath [ pkgs.fzf ])
              ];
              flakeIgnore = [ "E501" ];
            }
            (
              builtins.replaceStrings [ "@template@" "@subscriptions@" ] [ "${./clash-script.js}" subscriptions ]
                (builtins.readFile ./netsel.py)
            );
      in
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        home.packages = [ netsel ];

        sops.secrets."clash/subscriptions" = { };

        # Verge 的配置文件由它自己反复重写，不能 symlink；每次 switch 把订阅、分流脚本、外部控制器
        # 与 secret 收敛到期望值。有差异时会重启 Verge（网络断几秒），没差异时什么都不做。
        # 排在 sops-nix 之后：订阅清单由它解密（darwin 上是异步的 launchd agent，netsel 会再等一下）。
        home.activation.clashVerge = lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
          run ${netsel}/bin/netsel setup || echo "netsel setup 失败（不影响本次 switch）" >&2
        '';
      };
  };
}
