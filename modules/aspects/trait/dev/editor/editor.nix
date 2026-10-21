# 问：写代码的地方。EDITOR / VISUAL 在这里统一定义，各编辑器子 aspect 不要各自再设。
{ den, ... }:
{
  den.aspects.dev.editor = {
    includes = [
      den.aspects.dev.editor.neovim
      den.aspects.dev.editor.helix
    ];

    # nvim-lazy 是 neovim/lazyvim 提供的入口（NVIM_APPNAME=lazyvim），与 vi / vim / nvim
    # 三个别名指向同一处；直接写 nvim 会启动一份没有任何配置的裸 neovim。
    homeManager.home.sessionVariables = {
      EDITOR = "nvim-lazy";
      VISUAL = "nvim-lazy";
    };
  };
}
