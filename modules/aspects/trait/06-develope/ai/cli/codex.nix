# 关掉它你会失去：Codex CLI 本体。共享资产（skills / prompts / hooks /
# 全局指令）由同级目录各自挂载，不在这里。
{ inputs, ... }:
{
  den.aspects.dev.ai.cli.codex.homeManager =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      # 同 claude.nix 的理由，且更强烈：~/.codex/config.toml 几乎全是运行时状态——
      # projects.*.trust_level（每信任一个目录就写一次）、hooks.state.*.trusted_hash、
      # marketplaces.*.last_updated、[desktop] 的主题与窗口偏好。接管成只读会让
      # Codex 无法信任新项目、无法改主题。模块只在 settings 非空时才写该文件。
      programs.codex = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.codex;
      };
    };
}
