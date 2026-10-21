# 关掉它你会失去：Cursor 读到共享 prompt 的那条链接。
# 只有配置没有本体：Cursor 是手装的 .app，本仓库不管。
{ ... }:
{
  den.aspects.dev.ai.agent.cursor.homeManager =
    { config, ... }:
    {
      # skills 不用接线：~/.agents/skills 本来就在 Cursor 的 skill 根白名单里。
      home.file.".cursor/commands".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/prompts";
    };
}
