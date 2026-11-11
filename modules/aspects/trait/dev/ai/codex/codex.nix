# 关掉它你会失去：Codex CLI 本体、ACP 接入、桌面客户端，以及终端里子 agent 与长命令的运行指示。
{ inputs, ... }:
{
  # 桌面客户端用的是 chatgpt cask（ChatGPT.app，bundle id 已是 com.openai.codex）；
  # 另一个 codex-app cask 装的是独立的 Codex.app，两者别同时装。
  den.aspects.dev.ai.codex.darwin = {
    homebrew.casks = [ "chatgpt" ];
  };

  den.aspects.dev.ai.codex.homeManager =
    { pkgs, lib, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;

      # Codex 只把主对话报给终端（OSC 7501 根记录），一轮结束就显示完成；这组 hook 把子 agent
      # 与跑得久的命令（含后台 terminal）补报成子记录，Rex 等终端据此继续显示运行中。
      programStatus = pkgs.writers.writePython3Bin "codex-program-status" {
        flakeIgnore = [ "E501" ];
      } (
        builtins.readFile ./program-status/codex-program-status.py
      );

      hook = {
        type = "command";
        command = "${lib.getExe programStatus} hook";
        timeout = 5;
      };

      # 以插件形式加载 hook，不接管手工维护的 ~/.codex/hooks.json。
      # hook 要先信任才会跑：Codex 里 /hooks 审一次；脚本改动后 store 路径变了，需要重新审。
      programStatusPlugin = pkgs.runCommand "codex-plugin-program-status" { } ''
        install -Dm644 ${
          pkgs.writers.writeJSON "plugin.json" {
            name = "program-status";
            version = "0.1.0";
            description = "Report subagents and long-running commands to the terminal via OSC 7501";
          }
        } $out/.codex-plugin/plugin.json
        install -Dm644 ${
          pkgs.writers.writeJSON "hooks.json" {
            hooks = {
              SubagentStart = [ { hooks = [ hook ]; } ];
              SubagentStop = [ { hooks = [ hook ]; } ];
              PreToolUse = [
                {
                  matcher = "Bash";
                  hooks = [ hook ];
                }
              ];
              PostToolUse = [
                {
                  matcher = "Bash";
                  hooks = [ hook ];
                }
              ];
            };
          }
        } $out/hooks/hooks.json
      '';

      # 不用 programs.codex.plugins：它把个人 marketplace 写到 ~/.agents/plugins/marketplace.json，
      # 而集群机器上 ~/.agents 是指向共享目录 /nfs/aor/agents 的软链。这里改成一个放在 store
      # 里的本地 marketplace，config.toml 只登记它的路径；插件按 Codex 的安装布局直接放进
      # plugins/cache/<marketplace>/<plugin>/local（本地插件的版本目录固定叫 local）。
      marketplaceName = "infra";
      marketplace = pkgs.runCommand "codex-marketplace-${marketplaceName}" { } ''
        mkdir -p $out/plugins
        cp -r ${programStatusPlugin} $out/plugins/program-status
        install -Dm644 ${
          pkgs.writers.writeJSON "marketplace.json" {
            name = marketplaceName;
            interface.displayName = "Infra";
            plugins = [
              {
                name = "program-status";
                source = {
                  source = "local";
                  path = "./plugins/program-status";
                };
                policy = {
                  installation = "INSTALLED_BY_DEFAULT";
                  authentication = "ON_INSTALL";
                };
                category = "Productivity";
              }
            ];
          }
        } $out/.agents/plugins/marketplace.json
      '';
    in
    {
      programs.codex = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.codex;
        marketplaces.${marketplaceName} = marketplace;
        settings = {
          features.plugin_hooks = true;
          plugins."program-status@${marketplaceName}".enabled = true;
        };
        # config.toml 里有 Codex 自己写的状态（hook 信任记录、项目信任等），只合并、不接管
        mutableSettings = true;
      };

      home.file.".codex/plugins/cache/${marketplaceName}/program-status/local" = {
        source = programStatusPlugin;
        force = true;
      };

      # ACP adapter 当前主要供 Obsidian 的 Agent 插件启动 Codex。
      home.packages = [ inputs.llm-agents.packages.${system}.codex-acp ];
    };
}
