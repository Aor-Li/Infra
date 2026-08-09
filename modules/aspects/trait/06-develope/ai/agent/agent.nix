{ den, ... }:
{
  flake-file.inputs.llm-agents.url = "github:numtide/llm-agents.nix";

  den.aspects.dev.ai.agent =
    let
      # llm-agents 里的 codex 是 Rust 包，没有 numtide 的缓存就得从源码编译。
      cache.nix.settings = {
        extra-substituters = [ "https://cache.numtide.com" ];
        extra-trusted-public-keys = [
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        ];
      };
    in
    {
      os = cache;

      # home 侧必须再写一次：nix/conf.nix 有意用整体覆盖的 `substituters`（见那里
      # 关于镜像优先级的注释），而它同样作用于 homeManager，于是 ~/.config/nix/nix.conf
      # 会把系统层合并出来的 numtide 顶掉——用户级配置比 /etc/nix/nix.conf 后读。
      homeManager = cache;

      includes = [
        den.aspects.dev.ai.agent.claude
        den.aspects.dev.ai.agent.codex
        den.aspects.dev.ai.agent.cursor
      ];
    };
}
