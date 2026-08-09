# 关掉它你会失去：Claude Code 本体。共享资产（skills / prompts / hooks /
# 全局指令）由同级目录各自挂载，不在这里。
{ inputs, ... }:
{
  den.aspects.dev.ai.cli.claude.homeManager =
    { pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      # TODO: secrets（sops）搭好后再补 provider 认证配置——
      # auth token 与 ~/.claude/settings.json（ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN）。
      #
      # 刻意不设 settings：settings.json 是 Claude 的运行时状态（主题、model、
      # effortLevel、enabledPlugins、extraKnownMarketplaces 都由它自己写）。一旦
      # 这里给了值，home-manager 就把该文件变成只读 store 链接，装插件和改配置全部失败。
      # 模块只在 settings/marketplaces 非空时才接管这个文件，留空即把所有权还给 Claude。
      programs.claude-code = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.claude-code;
      };
    };
}
