# 共享提示词

`_prompts/<名字>.md` = 一条 `/<名字>` 命令。整目录挂到 `~/.claude/commands` 与
`~/.cursor/commands`，改完即刻生效，新增文件也不用 rebuild。

README 放在这一层而不是 `_prompts/` 里面：那个目录里每个 `.md` 都会变成一条命令。

## 谁支持

| Agent | 位置 |
| --- | --- |
| Claude Code | `~/.claude/commands/*.md` |
| Cursor | `~/.cursor/commands/*.md` |
| Codex | **没有**。自定义 prompt 在 0.117 被移除，`~/.codex/prompts` 不再被扫描 |

## 什么时候该写成 skill 而不是 prompt

prompt 只能显式唤起，且只有两家支持。skill 三家都支持，还能被隐式触发。
所以默认写 skill；只有"这条东西必须由我手动触发、不希望 agent 自作主张用"
才写 prompt——而这一点 skill 也能表达（frontmatter 里
`allow_implicit_invocation = false` / `disable-model-invocation: true`）。

实际的判据只剩一条：**要不要 Codex 也能用**。要 → skill。
