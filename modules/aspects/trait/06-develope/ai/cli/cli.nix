# 关掉它你会失去：所有 agent 的命令行本体（同级的 skills / prompts / hooks
# 只负责往它们的配置目录里挂东西，不装程序）。
{ den, ... }:
{
  den.aspects.dev.ai.cli.includes = [
    den.aspects.dev.ai.cli.claude
    den.aspects.dev.ai.cli.codex
  ];
}
