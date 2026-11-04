# Claude Code hook：把 subagent 与后台 Bash 作为子记录，用 OSC 7501（Program Status
# Protocol）报给终端。Claude Code 自己只报根记录，主对话这一轮一结束就是 done，
# 后台还在跑的东西终端看不到；子记录与根记录并存，Rex 据此继续转圈。
#
#   claude-program-status hook               由 hook 调用，stdin 是 hook 的 JSON 输入
#   claude-program-status watch TTY PID ID   后台 Bash 的监视进程，由 hook 自己拉起
#
# 记录 id：agent/<agent_id>（subagent）、bg/<task_id>（后台 Bash）。
# 协议：https://www.superlogical.com/rex/docs/build/program-status

app="claude-code"

# OSC 7501 报告。$1 tty，$2 状态，$3 id，$4 title，$5 msg（后两者为纯文本，可为空）
report() {
  local tty=$1 state=$2 id=$3 title=${4:-} msg=${5:-} body
  body="state=$state:id=$id"
  if [[ $state != clear ]]; then
    body+=":app=$app"
    [[ -n $title ]] && body+=":title=$(printf '%s' "$title" | base64 -w0)"
    [[ -n $msg ]] && body+=":msg=$(printf '%s' "$msg" | base64 -w0)"
  fi
  # shellcheck disable=SC1003 # 结尾是 ST（ESC \），不是转义单引号
  printf '\e]7501;%s\e\\' "$body" >"$tty" 2>/dev/null || true
}

# id 段只允许 [A-Za-z0-9_.+-]{1,32}，否则整条报告被丢弃
segment() {
  local s
  s=$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.+-' '_')
  printf '%s' "${s:0:32}"
}

# hook 进程没有终端：沿进程链往上找第一个有 tty 的祖先，即 Claude Code 本体。
# 输出 "PID /dev/pts/N"；找不到（非交互运行）则失败。
find_claude() {
  local pid=$PPID tty ppid
  while [[ $pid -gt 1 ]]; do
    read -r ppid tty < <(ps -o ppid=,tty= -p "$pid") || return 1
    if [[ -n $tty && $tty != "?" ]]; then
      printf '%s /dev/%s\n' "$pid" "$tty"
      return 0
    fi
    pid=$ppid
  done
  return 1
}

# 后台 Bash 的输出文件结束时以 "[exited with code N]" 收尾；看到它就清掉记录。
# Claude Code 退出时终端会自己丢弃 working 记录，监视进程跟着退出，不再写 tty。
watch_task() {
  local tty=$1 claude=$2 task=$3 file="" root last
  root="${CLAUDE_CODE_TMPDIR:-${TMPDIR:-/tmp}}/claude-$(id -u)"
  while kill -0 "$claude" 2>/dev/null; do
    [[ -z $file ]] && file=$(find "$root" -path "*/tasks/$task.output" -print -quit 2>/dev/null)
    if [[ -n $file ]]; then
      last=$(tail -n 1 "$file" 2>/dev/null) || last=""
      if [[ $last =~ ^\[exited\ with\ code\ [0-9]+\]$ ]]; then
        report "$tty" clear "bg/$(segment "$task")"
        return 0
      fi
    fi
    sleep 2
  done
}

handle_hook() {
  local input event claude_pid tty id
  input=$(cat)
  read -r claude_pid tty < <(find_claude) || return 0
  event=$(jq -r '.hook_event_name // empty' <<<"$input")

  case $event in
  SubagentStart)
    id="agent/$(segment "$(jq -r '.agent_id // empty' <<<"$input")")"
    report "$tty" working "$id" "$(jq -r '.agent_type // "subagent"' <<<"$input")"
    ;;
  SubagentStop)
    id="agent/$(segment "$(jq -r '.agent_id // empty' <<<"$input")")"
    report "$tty" clear "$id"
    ;;
  PostToolUse)
    case $(jq -r '.tool_name // empty' <<<"$input") in
    Bash)
      local task msg
      task=$(jq -r '.tool_response.backgroundTaskId // empty' <<<"$input")
      [[ -n $task ]] || return 0
      # msg 必须是单行、不含控制字符
      msg=$(jq -r '(.tool_input.description // .tool_input.command // "")
                   | explode | map(if . < 32 or (. >= 127 and . < 160) then 32 else . end)
                   | implode | .[0:160]' <<<"$input")
      report "$tty" working "bg/$(segment "$task")" "background" "$msg"
      setsid "$0" watch "$tty" "$claude_pid" "$task" </dev/null >/dev/null 2>&1 &
      ;;
    TaskStop | KillShell)
      local task
      task=$(jq -r '.tool_input.task_id // .tool_input.shell_id // empty' <<<"$input")
      if [[ -n $task ]]; then report "$tty" clear "bg/$(segment "$task")"; fi
      ;;
    esac
    ;;
  esac
}

case ${1:-} in
hook) handle_hook ;;
watch) watch_task "$2" "$3" "$4" ;;
*)
  echo "usage: claude-program-status hook | watch TTY PID TASK" >&2
  exit 2
  ;;
esac
