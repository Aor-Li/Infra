# 关掉它你会失去：caam——Claude / Codex / Gemini 等 agent CLI 的多账号保存与秒切。
#
# 上游不在 nixpkgs / llm-agents.nix 里，这里从源码打包。
# 注意 LICENSE 是「MIT + OpenAI/Anthropic rider」，不是纯 MIT。
{ ... }:
{
  den.aspects.dev.ai.caam.homeManager =
    { pkgs, ... }:
    let
      version = "0.1.25";
      module = "github.com/Dicklesworthstone/coding_agent_account_manager";
      caam = pkgs.buildGoModule {
        pname = "caam";
        inherit version;
        src = pkgs.fetchFromGitHub {
          owner = "Dicklesworthstone";
          repo = "coding_agent_account_manager";
          rev = "v${version}";
          hash = "sha256-p/T3J3OBFhaYqpQzKWuM/w8Ro/3RDMeVLBsmF/yjQcY=";
        };
        vendorHash = "sha256-RM7x986zz5iMtqlhbfEjsuCm03xAEylujyPhSESwrQY=";
        subPackages = [ "cmd/caam" ];
        env.CGO_ENABLED = 0;
        ldflags = [
          "-s"
          "-w"
          "-X ${module}/internal/version.Version=${version}"
        ];
        # 上游测试会读写 $HOME 下各 agent 的凭据目录，沙箱里跑不了。
        doCheck = false;
        meta = {
          description = "Coding Agent Account Manager: switch AI coding CLI subscription accounts";
          homepage = "https://github.com/Dicklesworthstone/coding_agent_account_manager";
          mainProgram = "caam";
        };
      };
    in
    {
      home.packages = [ caam ];
    };
}
