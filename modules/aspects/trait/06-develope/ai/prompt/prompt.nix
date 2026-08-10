# 关掉它你会失去：手打 `/` 唤起的那批自定义提示词。
# mine/ 是纯载荷目录，别往里放 .nix——import-tree 会把它当模块导入。
{ ... }:
{
  den.aspects.dev.ai.prompt.homeManager =
    { config, ... }:
    {
      # 一个 .md 一条命令。整目录挂，新增一个文件不用 rebuild。
      home.file.".agents/prompts".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Infra/modules/aspects/trait/06-develope/ai/prompt/mine";
    };
}
