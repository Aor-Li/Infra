# 关掉它你会失去：GitHub CLI 及其为 Git HTTPS 操作提供的凭据助手。
{
  den.aspects.dev.vcs.gh = {
    homeManager = {
      programs.gh = {
        enable = true;
        gitCredentialHelper.enable = true;
      };
    };
  };
}
