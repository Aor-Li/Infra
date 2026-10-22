# 关掉它你会失去：所有 AI agent 本体与各自的私有配置。
#
# 一个 agent 一个叶子。skill / prompt 等资产不在这里统一分发，由各 agent 按自己
# 默认的方式管理（如 Claude 的插件市场）——共享目录会让各家的私有写入与扫描规则
# 互相干扰。
{ den, ... }:
{
  flake-file.inputs.llm-agents.url = "github:numtide/llm-agents.nix";

  den.aspects.dev.ai =
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

      # standalone home 必须再写一次：nix/conf.nix 有意用整体覆盖的 `substituters`（见那里
      # 关于镜像优先级的注释），它会写进 ~/.config/nix/nix.conf，把这里的 numtide 顶掉。
      # 作为系统模块时 HM 不写 nix.conf（同样见 conf.nix），系统层那份就够了。
      homeManager =
        {
          lib,
          osConfig ? null,
          ...
        }:
        lib.mkIf (osConfig == null) cache;

      includes = [
        den.aspects.dev.ai.claude
        den.aspects.dev.ai.codex
        den.aspects.dev.ai.opencode
        den.aspects.dev.ai.pi
      ];
    };
}
