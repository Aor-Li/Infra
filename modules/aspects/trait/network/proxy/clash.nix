# 关掉它你会失去：Clash Verge 代理客户端，以及按 TurboAI / AliCloud / 国内 / 国外 / AI 分流、在终端里看状态和切节点的 `netsel`。
#
# 订阅清单（有哪些订阅、顺序、哪份是汇总订阅）是所有机器共享的事实，放在 sops：
# entity/users/aor/secrets.yaml 的 clash.subscriptions，一个 YAML 列表字符串
#   - name: Forest            # 分组名；provider 名取小写
#     url: https://…          # 订阅链接带 token，所以加密
#   - name: JMS
#     url: https://…
#     summary: true           # 恰好一项：全局脚本只在这份订阅激活时改写
#     ai: true                # 可选：所有节点访问 AI 的出口都实测在支持地区（非 HK/MO/CN/RU），
#                             # 单独成「AI 备用」一档，排在 AI 美国之后；不再参与按节点名猜地区的分档
# 顺序即「自动容灾」的优先级。改订阅只改这里，各机器 switch 后一致。
#
# Clash Verge 一次只激活一份订阅。全局扩展脚本只在汇总订阅激活时启用 netsel 分流；
# 选其他订阅时保留其原生节点和分组，供现有节点故障时救急。clash-script.js 用
# proxy-providers 同时拉取清单里的所有订阅，再按 TurboAI / AliCloud / 国内 / 国外 / AI 分组。
# `netsel setup` 把清单套进模板写到 Verge 的 profiles/Script.js；清单里有、Verge 里还没有的
# 订阅经 clash://install-config deep link 交给 Verge 导入（profiles.yaml 归 Verge 写，这里不碰）。
#
# switch 不改动代理：改代理要重启 Verge（断网几秒）、要拉起 GUI，激活环境里也容易失败且没人看。
# activation 只跑 `netsel setup --check` 报告差异；真正应用由你手动 `netsel setup`。
# 新机器第一次 switch 后，打开一次 Clash Verge，再执行一次 `netsel setup`。
#
# Verge 自己的配置（clash-verge.yaml / verge.yaml）只收敛 netsel 依赖的几项：开启外部控制器、
# 只听 127.0.0.1。控制器 secret 不管，用 Verge 当时的值（理由见 netsel.py 的 CONTROLLER 处）。
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

        # 只检查不改动（见文件头）：订阅清单由 sops-nix 解密，darwin 上是异步的 launchd agent，
        # 所以排在 sops-nix 之后，netsel 再等它最多 15 秒。
        home.activation.clashVerge = lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
          run ${netsel}/bin/netsel setup --check || echo "netsel setup --check 失败（不影响本次 switch）" >&2
        '';
      };
  };
}
