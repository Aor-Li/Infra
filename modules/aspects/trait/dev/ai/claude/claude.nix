# 关掉它你会失去：Claude Code CLI 本体、Claude 桌面客户端，以及终端里后台任务的运行指示。
{ inputs, ... }:
{
  den.aspects.dev.ai.claude.darwin = {
    homebrew.casks = [ "claude" ];
  };

  den.aspects.dev.ai.claude.homeManager =
    { pkgs, lib, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;

      # Claude Code 只把主对话报给终端（OSC 7501 根记录），这一轮一结束就显示完成；
      # 这组 hook 把 subagent 与后台 Bash 补报成子记录，Rex 等终端据此继续显示运行中。
      programStatus = pkgs.writeShellApplication {
        name = "claude-program-status";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
          jq
          procps
          util-linux # setsid
        ];
        text = builtins.readFile ./program-status/claude-program-status.sh;
      };

      hook = {
        type = "command";
        command = "${lib.getExe programStatus} hook";
        timeout = 5;
      };

      # 以 personal plugin 的形式加载 hook：不需要接管手工维护的 settings.json
      programStatusPlugin = pkgs.runCommand "claude-program-status-plugin" { } ''
        install -Dm644 ${
          pkgs.writers.writeJSON "plugin.json" {
            name = "program-status";
            description = "Report subagents and background Bash to the terminal via OSC 7501";
          }
        } $out/.claude-plugin/plugin.json
        install -Dm644 ${
          pkgs.writers.writeJSON "hooks.json" {
            hooks = {
              SubagentStart = [ { hooks = [ hook ]; } ];
              SubagentStop = [ { hooks = [ hook ]; } ];
              PostToolUse = [
                {
                  matcher = "Bash|TaskStop|KillShell";
                  hooks = [ hook ];
                }
              ];
            };
          }
        } $out/hooks/hooks.json
      '';
    in
    {
      programs.claude-code = {
        enable = true;
        package = inputs.llm-agents.packages.${system}.claude-code;
        plugins.program-status = programStatusPlugin;
      };
    };
}
