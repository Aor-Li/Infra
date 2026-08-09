# 共享 skill 库

一个 skill = 一个目录 + 里面的 `SKILL.md`（YAML frontmatter 写 `name` 与
`description`，正文写指令）。可选的 `scripts/` `references/` `assets/` 按需加。
`description` 决定 agent 会不会在该用的时候想起它，比正文更值得反复打磨。

自己写的放 `_skills/<名字>/SKILL.md`。第三方 skill 包不进仓库，在 `skills.nix`
里加 flake input，版本由 `flake.lock` 钉住。

## 挂到哪里

正本是 `~/.agents/skills/` —— 跨 agent 的中立位置，不属于任何一家。里面每个
skill 是一条 symlink：自己写的指回本仓库，第三方的指进 nix store。

| Agent | 怎么读到 |
| --- | --- |
| Codex | 原生扫 `~/.agents/skills`（它的 USER scope） |
| Claude Code | `~/.claude/skills` 是一条指向 `~/.agents/skills` 的 symlink |
| Cursor | skill 根白名单里同时有这两个路径，自动读到 |

**必须平铺成一层。** Claude Code 的加载器对 skills 根目录只做一层 readdir，
对每个条目找 `<name>/SKILL.md`，不递归；Codex 和 Cursor 递归，平铺对它们也成立。
所以整个库按 `<skill 名> -> 源目录` 逐个挂，而不是整目录挂一条。

**Cursor 里会看到重复。** 它同时扫 `.agents/skills` 和 `.claude/skills`，同一个
skill 可能列两次。无解：Claude 只认 `.claude/skills`、Codex 不认 `.claude/skills`，
覆盖三家至少要两个挂载点，而 Cursor 两个都读。

## 改动的生效方式

- **改已有 skill 的内容**：即刻生效，symlink 直接指向本仓库。
- **新增 / 删除 skill**：要 rebuild。平铺挂载靠求值期的 `builtins.readDir`
  枚举目录，Nix 不知道你新建了目录。

## 和各 agent 自己的插件市场的关系

Claude Code、Codex、Cursor 各有自己的 plugin marketplace，装出来的 skill 落在
`~/.claude/plugins/`、`~/.codex/plugins/`、`~/.cursor/plugins/`。那条路是**每台机器
各装一遍**的命令式操作，本仓库不管；同一个包两条路都装会在列表里重复出现。
要么全走这里，要么全走市场。
