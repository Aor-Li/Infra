"""Codex hook：把子 agent 与跑得久的命令（含后台 terminal）作为子记录，用 OSC 7501 报给终端。

Codex 自己只报根记录，一轮结束就是 done，后台 terminal 和还在跑的子 agent 终端看不到；
子记录与根记录并存，Rex 据此继续转圈。与 dev/ai/claude 的 claude-program-status 同一思路，
但 Codex 有两处不同：

- hook 不一定跑在 TUI 下面。TUI 内嵌 app-server 时，hook 是 TUI 的子进程，沿进程链能找到终端；
  TUI 连到共享的 app-server 守护进程时，hook 是守护进程的子进程，没有终端，只能按会话 cwd
  去找唯一一个工作目录相同、带终端的 codex TUI，找不到或不唯一就不报。
- 后台 terminal（unified exec）的 PostToolUse 要等命令结束才来，所以开始时机取 PreToolUse：
  拉起一个监视进程，找到这条命令的进程，跑满 MIN_RUNTIME 秒才报 working，进程退出时清掉。
  短命令因此不会闪一条记录。

  codex-program-status hook                          由 hook 调用，stdin 是 hook 的 JSON 输入
  codex-program-status watch TTY OWNER ID SPEC_FILE  命令的监视进程，由 hook 自己拉起

记录 id：agent/<agent_id>（子 agent）、cmd/<tool_use_id>（命令）。
协议：https://www.superlogical.com/rex/docs/build/program-status
"""

import base64
import json
import os
import re
import subprocess
import sys
import time

APP = "codex"
MIN_RUNTIME = 10  # 秒；命令跑满这么久才算「长命令」
FIND_TIMEOUT = 20  # 秒；PreToolUse 之后这么久还没找到命令进程就放弃


def b64(text):
    return base64.b64encode(text.encode()).decode()


def oneline(text, limit=160):
    """msg / title 必须是单行、不含控制字符。"""
    return re.sub(r"[\x00-\x1f\x7f-\x9f]+", " ", text).strip()[:limit]


def segment(s):
    """id 段只允许 [A-Za-z0-9_.+-]{1,32}，否则整条报告被丢弃。取末尾 32 位，调用 id 的前缀都一样。"""
    s = re.sub(r"[^A-Za-z0-9_.+-]", "_", s or "") or "_"
    return s[-32:]


def report(tty, state, rid, title="", msg=""):
    body = f"state={state}:id={rid}"
    if state != "clear":
        body += f":app={APP}"
        if title:
            body += f":title={b64(oneline(title))}"
        if msg:
            body += f":msg={b64(oneline(msg))}"
    try:
        with open(tty, "w") as fh:
            fh.write(f"\033]7501;{body}\033\\")
    except OSError:
        pass


# ---- 进程 --------------------------------------------------------------------------------

def ppid_of(pid):
    try:
        with open(f"/proc/{pid}/stat") as fh:
            # comm 可能含空格和括号，ppid 在最后一个 ')' 之后的第二个字段
            return int(fh.read().rpartition(")")[2].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def tty_of(pid):
    for fd in (0, 1, 2):
        try:
            path = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if path.startswith("/dev/pts/") or path.startswith("/dev/tty"):
            return path
    return None


def comm_of(pid):
    try:
        with open(f"/proc/{pid}/comm") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def argv_of(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            return fh.read().split(b"\0")
    except OSError:
        return []


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def my_pids():
    uid = os.getuid()
    for name in os.listdir("/proc"):
        if name.isdigit():
            try:
                if os.stat(f"/proc/{name}").st_uid == uid:
                    yield int(name)
            except OSError:
                continue


def find_terminal(cwd):
    """返回 (owner_pid, tty)：owner 是 TUI 进程，它退出时监视进程跟着退出；找不到返回 None。

    沿进程链取最外层带终端的祖先（Rex pane 里的 shell），owner 取最近的 codex 祖先。
    """
    pid, tty, owner = os.getppid(), None, None
    while pid > 1:
        if owner is None and comm_of(pid) == "codex":
            owner = pid
        tty = tty_of(pid) or tty
        pid = ppid_of(pid)
    if tty and owner:
        return owner, tty

    # 守护进程模式：按工作目录找唯一的 codex TUI
    if not cwd:
        return None
    hits = []
    for pid in my_pids():
        if comm_of(pid) != "codex" or not tty_of(pid):
            continue
        try:
            if os.readlink(f"/proc/{pid}/cwd") == cwd:
                hits.append(pid)
        except OSError:
            continue
    if len(hits) != 1:
        return None
    return hits[0], tty_of(hits[0])


# ---- 命令监视 ----------------------------------------------------------------------------

def command_pids(cmd):
    """argv 里某一项恰好等于这条命令的进程（bash -lc CMD，以及外面套的 sandbox 包装）。"""
    want = cmd.encode()
    return {pid for pid in my_pids() if pid != os.getpid() and want in argv_of(pid)}


def watch(tty, owner, rid, spec_file):
    with open(spec_file) as fh:
        spec = json.load(fh)
    os.unlink(spec_file)
    cmd, before = spec["cmd"], set(spec["before"])

    deadline = time.time() + FIND_TIMEOUT
    pids = set()
    while not pids:
        if time.time() > deadline or not alive(owner):
            return
        time.sleep(0.5)
        pids = command_pids(cmd) - before

    started = time.time()
    reported = False
    while alive(owner) and any(alive(p) for p in pids):
        if not reported and time.time() - started >= MIN_RUNTIME:
            report(tty, "working", rid, "command", cmd)
            reported = True
        time.sleep(1 if reported else 0.5)
    if reported:
        report(tty, "clear", rid)


# ---- hook --------------------------------------------------------------------------------

def handle_hook():
    data = json.load(sys.stdin)
    event = data.get("hook_event_name", "")
    # SubagentStop / Stop 退出码 0 时要求 stdout 是 JSON
    if event == "SubagentStop":
        print("{}")

    found = find_terminal(data.get("cwd") or "")
    if not found:
        return
    owner, tty = found

    if event == "SubagentStart":
        rid = "agent/" + segment(data.get("agent_id"))
        report(tty, "working", rid, data.get("agent_type") or "subagent")
    elif event == "SubagentStop":
        report(tty, "clear", "agent/" + segment(data.get("agent_id")))
    elif event in ("PreToolUse", "PostToolUse") and data.get("tool_name") == "Bash":
        rid = "cmd/" + segment(data.get("tool_use_id"))
        if event == "PostToolUse":
            report(tty, "clear", rid)
            return
        cmd = (data.get("tool_input") or {}).get("command")
        if isinstance(cmd, list):
            cmd = cmd[-1] if cmd else ""
        if not cmd:
            return
        # 同一条命令可能还有更早的一份在跑，要排除掉。必须在 hook 返回前记下：hook 一返回 Codex
        # 就启动命令，等监视进程起来再看，新命令已经在里面了。
        # 命令文本可能很长且带换行，连同这份名单经文件交给监视进程。
        spec = {"cmd": cmd, "before": sorted(command_pids(cmd))}
        spec_file = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"codex-program-status-{os.getpid()}")
        with open(spec_file, "w") as fh:
            json.dump(spec, fh)
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "watch", tty, str(owner), rid, spec_file],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )


def main():
    args = sys.argv[1:]
    if args[:1] == ["hook"]:
        try:
            handle_hook()
        except Exception:  # noqa: BLE001 — hook 出错不能影响 Codex
            pass
        return 0
    if args[:1] == ["watch"] and len(args) == 5:
        watch(args[1], int(args[2]), args[3], args[4])
        return 0
    print("usage: codex-program-status hook | watch TTY OWNER ID SPEC_FILE", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
