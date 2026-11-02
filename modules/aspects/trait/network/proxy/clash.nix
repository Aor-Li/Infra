# 关掉它你会失去：Clash Verge 代理客户端，以及按 DGX / 国内 / 国外分流、在终端里看状态和切节点的 `netsel`。
#
# Clash Verge 一次只激活一份订阅，所以分流不写在订阅上，而是写在 Verge 的全局扩展脚本里：
# clash-script.js 用 proxy-providers 同时拉取 Vikings 与 JMS，再按 DGX / 国内 / 国外 / AI 分组。
# 订阅链接带 token，不进仓库——`netsel setup` 从 Verge 的 profiles.yaml 读出链接，套进模板，
# 写到 Verge 的 profiles/Script.js。Verge 和这个文件都由 GUI 管，仓库只提供模板与工具。
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
      { lib, pkgs, ... }:
      let
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
              builtins.replaceStrings [ "@template@" ] [ "${./clash-script.js}" ] (builtins.readFile ./netsel.py)
            );
      in
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        home.packages = [ netsel ];

        # Verge 的配置文件由它自己反复重写，不能 symlink；每次 switch 把分流脚本、外部控制器与
        # secret 收敛到期望值。有差异时会重启 Verge（网络断几秒），没差异时什么都不做。
        home.activation.clashVerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${netsel}/bin/netsel setup || echo "netsel setup 失败（不影响本次 switch）" >&2
        '';
      };
  };
}
