{ den, ... }:
{
  flake-file.inputs = {
    llm-agents.url = "github:numtide/llm-agents.nix";

    # 第三方 skill 包。不是 flake，只当源码树用。
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };
  };

  den.aspects.dev.ai =
    let
      # numtide 的缓存：llm-agents 里的 codex 是 Rust 包，没有它就得从源码编译。
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
      # 只在 os 侧配的话这条缓存是空转的。
      homeManager = cache;

      # 一层按"agent 的哪一部分"分：cli 是程序本体，其余四个是喂给它们的共享资产。
      # 这么切是因为改动的单位就是资产——加一个 skill、调一条 hook，改的是一个资产
      # 在三家的挂载，而不是某一家 agent 的全部配置。
      #
      # Cursor 没有自己的条目：它的本体是手装的 .app，本仓库不管；而它读 skills 的
      # 路径白名单里就有 Claude 与 Codex 的目录，共享资产由各资产模块直接挂给它。
      includes = [
        den.aspects.dev.ai.cli
        den.aspects.dev.ai.instructions
        den.aspects.dev.ai.skills
        den.aspects.dev.ai.prompts
        den.aspects.dev.ai.hooks
      ];
    };
}
