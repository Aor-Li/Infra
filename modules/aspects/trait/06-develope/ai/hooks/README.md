# Agent hooks

hook = 在 agent 的生命周期事件（工具调用前后、会话开始结束、提交 prompt 前）上
跑一段自己的逻辑，脚本从 stdin 收 JSON、往 stdout 吐 JSON，可以放行、拦截、
改写输入或追加上下文。

## 现状：只有脚本能共用，接线不能

三家的事件名和文件结构都不一样，所以 `_hooks/` 下一家一份配置，`scripts/` 是
唯一共享的部分。

| Agent | 接线写在哪 | 事件名风格 | 本仓库管了吗 |
| --- | --- | --- | --- |
| Codex | `~/.codex/hooks.json` | `pre_tool_use` `session_start` … | 是，`_hooks/codex.json` |
| Cursor | `~/.cursor/hooks.json`（要 `"version": 1`） | `preToolUse` `beforeShellExecution` … | 是，`_hooks/cursor.json` |
| Claude Code | `~/.claude/settings.json` 的 `hooks` 键 | `PreToolUse` `PostToolUse` … | **否**，只挂了脚本 |

Claude 缺口的原因：它没有独立的 hooks 文件，接线只能写进 `settings.json`，而那
是运行时状态（主题、model、enabledPlugins 都由 Claude 自己写），本仓库刻意不接管
——见 `../cli/claude.nix` 的注释。等 secrets 那边把 settings 的所有权问题一起
解决时再补。

## 脚本放哪、怎么引用

脚本一律放 `_hooks/scripts/`，三家各自挂到自己的 hooks 目录下：

| Agent | 命令里写的路径 |
| --- | --- |
| Codex | `$HOME/.codex/hooks/scripts/<名字>` |
| Cursor | `hooks/scripts/<名字>`（用户级 hook 的相对路径以 `~/.cursor/` 为根） |
| Claude Code | `$HOME/.claude/hooks/scripts/<名字>` |

挂的是 `hooks/scripts/` 而不是 `hooks/` 本身：Codex 和 Cursor 都往 `hooks/state/`
写运行时状态，整目录接管会把状态写回本仓库。

写脚本时记得：**hook 进程的 `$PATH` 不等于你的交互 shell**。用到 `jq` `python3`
之类就要确认它确实在里面，否则 hook 会静默失败（默认 fail open）。
