# 关掉它你会失去：模糊搜索（Ctrl-R 历史、Ctrl-T 文件、Alt-C 目录）。
{
  den.aspects.dev.shell.util.fzf.homeManager = {
    programs.fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
    };
  };
}
