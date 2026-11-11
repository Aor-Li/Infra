"""hwstat: 并发 ssh 到一组主机，汇总 CPU / 内存 / GPU 使用情况与占用用户。"""

import argparse
import base64
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

DEFAULT_HOSTS = json.loads(r"""@HOSTS@""")
GROUPS = json.loads(r"""@GROUPS@""")
ARENA_REGISTRY = json.loads(r'''@ARENA@''')  # arena registry 目录（null = 不读），--tasks / --wait 用

# 在远端执行（bash -s 从 stdin 读）。只输出带标签的行，由本地解析；
# top 取第二帧才是真实的瞬时占用，并且只打印 %CPU > 0 的进程以减少传输量。
PROBE = r"""
export LC_ALL=C
echo "NPROC $(nproc)"
echo "LOAD $(cut -d' ' -f1 /proc/loadavg)"
free -b | awk '/^Mem:/ {print "MEM", $2, $7}'
{ top -b -n 2 -d 0.5 -w 512 2>/dev/null || top -b -n 2 -d 0.5; } | awk '
  /^top -/ {f++}
  f < 2 {next}
  /^%Cpu/ {print "CPU", $0; next}
  /^ *PID / {for (i = 1; i <= NF; i++) {if ($i == "USER") u = i; if ($i == "%CPU") c = i}; next}
  u && c && $c + 0 > 0 {print "P", $u, $c}'
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,uuid,utilization.gpu,memory.used,memory.total \
    --format=csv,noheader,nounits 2>/dev/null | sed 's/^/GPU /'
  apps=$(nvidia-smi --query-compute-apps=gpu_uuid,pid --format=csv,noheader,nounits 2>/dev/null)
  printf '%s\n' "$apps" | sed -n 's/^/APP /p'
  pids=$(printf '%s\n' "$apps" | awk -F', *' 'NF >= 2 {print $2}' | paste -sd, -)
  [ -n "$pids" ] && ps -o pid=,user= -p "$pids" 2>/dev/null | sed 's/^ */PS /'
  # 自己的 GPU 进程：沿父进程往上找同名（同一程序）的最顶层祖先当作「任务」，报告它的工作目录和命令行。
  # multiprocessing / torchrun 的 worker 因此能归到启动它的入口进程。
  me=$(id -un)
  for pid in $(printf '%s' "$pids" | tr , ' '); do
    [ "$(ps -o user= -p "$pid" 2>/dev/null)" = "$me" ] || continue
    root=$pid
    chain=$pid
    comm=$(ps -o comm= -p "$pid")
    while :; do
      pp=$(ps -o ppid= -p "$root" 2>/dev/null | tr -d ' ')
      [ -n "$pp" ] && [ "$pp" -gt 1 ] && [ "$(ps -o comm= -p "$pp")" = "$comm" ] || break
      root=$pp
      chain="$chain,$pp"
    done
    # 中间层进程（如编排脚本拉起的各角色）的 pid 也要报，arena 登记常记的是它们
    echo "JPIDS $root $chain"
    echo "JOB $pid $root $(readlink "/proc/$root/cwd" 2>/dev/null)"
    printf 'JCMD %s ' "$root"
    tr '\0' ' ' < "/proc/$root/cmdline" 2>/dev/null | cut -c1-2000
    echo
  done
else
  echo "NOGPU"
fi
"""

# GPU 被视为空闲：无计算进程、利用率为 0、显存占用低于此值（MiB）
IDLE_MEM_MIB = 1024
# -v 模式下用户 CPU 占用低于此核数不显示，过滤噪声
CPU_USER_MIN_CORES = 0.5


class Style:
    def __init__(self, enabled):
        self.enabled = enabled

    def __call__(self, text, code):
        return f"\033[{code}m{text}\033[0m" if self.enabled else text

    def level(self, text, pct):
        if pct is None:
            return text
        return self(text, "31" if pct >= 80 else "33" if pct >= 30 else "32")


def probe(host, timeout):
    cmd = [
        "ssh",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "LogLevel=ERROR",
        host,
        "bash -s",
    ]
    try:
        p = subprocess.run(cmd, input=PROBE, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return host, None, f"超时（>{timeout}s）"
    if p.returncode != 0 and "NPROC" not in p.stdout:
        lines = [ln.strip() for ln in p.stderr.splitlines() if ln.strip()]
        msg = lines[-1] if lines else f"ssh 退出码 {p.returncode}"
        return host, None, re.sub(r"^ssh:\s*", "", msg)
    return host, parse(p.stdout), None


def parse(out):
    r = {"nproc": 0, "load": None, "mem": None, "cpu": None,
         "cpu_users": {}, "gpus": [], "apps": [], "pid_user": {}, "has_gpu": True,
         "job_of": {}, "job_cwd": {}, "job_cmd": {}, "job_pids": {}}
    for line in out.splitlines():
        tag, _, rest = line.partition(" ")
        f = rest.split()
        try:
            if tag == "NPROC":
                r["nproc"] = int(f[0])
            elif tag == "LOAD":
                r["load"] = float(f[0])
            elif tag == "MEM":
                r["mem"] = (int(f[0]), int(f[1]))
            elif tag == "CPU":
                m = re.search(r"([\d.]+)\s*id", rest)
                if m:
                    r["cpu"] = 100.0 - float(m.group(1))
            elif tag == "P":
                r["cpu_users"][f[0]] = r["cpu_users"].get(f[0], 0.0) + float(f[1])
            elif tag == "GPU":
                idx, uuid, util, used, total = [x.strip() for x in rest.split(",")]
                r["gpus"].append({"idx": int(idx), "uuid": uuid, "util": num(util),
                                  "used": num(used), "total": num(total)})
            elif tag == "APP":
                uuid, pid = [x.strip() for x in rest.split(",")[:2]]
                r["apps"].append((uuid, pid))
            elif tag == "PS":
                r["pid_user"][f[0]] = f[1]
            elif tag == "JOB":
                pid, root, *cwd = rest.split(" ", 2)
                r["job_of"][pid] = root
                r["job_cwd"][root] = cwd[0].strip() if cwd else ""
            elif tag == "JPIDS":
                r["job_pids"].setdefault(f[0], set()).update(f[1].split(","))
            elif tag == "JCMD":
                root, _, cmd = rest.partition(" ")
                r["job_cmd"][root] = cmd.strip()
            elif tag == "NOGPU":
                r["has_gpu"] = False
        except (ValueError, IndexError):
            continue
    return r


def num(s):
    try:
        return float(s)
    except ValueError:
        return None  # [N/A] 等


def ranges(idxs):
    """[0,1,2,5] -> '0-2,5'"""
    idxs = sorted(set(idxs))
    out, i = [], 0
    while i < len(idxs):
        j = i
        while j + 1 < len(idxs) and idxs[j + 1] == idxs[j] + 1:
            j += 1
        out.append(str(idxs[i]) if i == j else f"{idxs[i]}-{idxs[j]}")
        i = j + 1
    return ",".join(out)


ANSI = re.compile(r"\033\[[0-9;]*m")
EIGHTHS = " ▏▎▍▌▋▊▉"
# 用户配色（256 色），按区分度从高到低排；刻意避开表示负载等级的红 / 黄 / 绿
PALETTE = ["38;5;33", "38;5;208", "38;5;201", "38;5;51", "38;5;141", "38;5;180", "38;5;217", "38;5;111"]
UNKNOWN = "38;5;250"  # 卡被占用但看不到进程属主（容器内进程等）
BORROW = "借用"
BAR_W = 8


def width(s):
    """终端显示宽度：去掉颜色码，中文等全角字符算两列。"""
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in ANSI.sub("", s))


def pad(s, w):
    return s + " " * (w - width(s))


def host_ranges(hosts):
    """['dgx0001','dgx0002','dgx0005','foo'] -> 'dgx0001-0002,0005 foo'"""
    groups, order = {}, []
    for h in hosts:
        m = re.fullmatch(r"(.*?)(\d+)", h)
        key = m.group(1) if m else h
        if key not in groups:
            groups[key] = []
            order.append(key)
        if m:
            groups[key].append(m.group(2))
    out = []
    for key in order:
        nums = groups[key]
        if not nums:
            out.append(key)
            continue
        w = len(nums[0])
        parts = ranges([int(n) for n in nums]).split(",")
        out.append(key + ",".join("-".join(f"{int(x):0{w}d}" for x in p.split("-")) for p in parts))
    return " ".join(out)


def parse_cards(spec):
    """'dgx0026:0-1,3' -> ('dgx0026', {0, 1, 3})；'dgx0019' -> ('dgx0019', None) 表示整机。"""
    host, _, idx = spec.partition(":")
    if not idx:
        return host, None
    out = set()
    for part in idx.split(","):
        a, _, b = part.partition("-")
        out.update(range(int(a), int(b or a) + 1))
    return host, out


def bar(pct, n, st, dim=False):
    """水平条：n 格宽，1/8 格精度，空余部分是暗色轨道。"""
    if pct is None:
        return st("?".ljust(n), "2")
    eighths = round(max(0.0, min(pct, 100.0)) / 100 * n * 8)
    full, rem = divmod(eighths, 8)
    filled = "█" * full + (EIGHTHS[rem] if rem else "")
    filled = st(filled, "2") if dim else st.level(filled, pct)
    return filled + st("░" * (n - len(ANSI.sub("", filled))), "2")


class Colors:
    """用户 -> 颜色。占卡多的用户先挑色，保证同屏最显眼的几位颜色互相区分最大。"""

    def __init__(self, cards):
        order = sorted(cards, key=lambda n: (-cards[n], n))
        self.map = {n: PALETTE[i % len(PALETTE)] for i, n in enumerate(n for n in order if n != "?")}

    def __getitem__(self, name):
        return self.map.get(name, UNKNOWN)


PY_FLAG = re.compile(r"-[BbdEhiIOqsSuvVx]+$")
TASK_NAME_MAX = 24


def task_name(cmd):
    """简短任务名：程序名（python 换成脚本名 / -m 模块的最后一段）+ 第一个位置参数（常是子命令）。"""
    toks = cmd.split()
    if not toks:
        return "?"
    prog, rest = os.path.basename(toks[0]), toks[1:]
    if prog.startswith("python"):
        while rest and PY_FLAG.match(rest[0]):
            rest.pop(0)
        if len(rest) >= 2 and rest[0] == "-m":
            prog, rest = rest[1].rsplit(".", 1)[-1], rest[2:]
        elif rest and not rest[0].startswith("-"):
            prog, rest = os.path.basename(rest[0]), rest[1:]
    name = prog
    if rest and not rest[0].startswith("-") and "/" not in rest[0] and "=" not in rest[0]:
        name += " " + rest[0]
    return name if len(name) <= TASK_NAME_MAX else name[:TASK_NAME_MAX - 1] + "…"


def analyze(r):
    """补上每张卡的占用者、是否空闲，以及内存占用率。"""
    uuid_idx = {g["uuid"]: g["idx"] for g in r["gpus"]}
    owners = {}  # idx -> [user]
    for uuid, pid in r["apps"]:
        idx = uuid_idx.get(uuid)
        if idx is None:
            continue
        name = r["pid_user"].get(pid, "?")
        if name not in owners.setdefault(idx, []):
            owners[idx].append(name)
    jobs = {}  # 任务根进程 pid -> {root, gpus, pids, cwd, cmd, name}
    for uuid, pid in r["apps"]:
        root = r["job_of"].get(pid)
        if root is None or uuid not in uuid_idx:
            continue
        cmd = r["job_cmd"].get(root, "")
        j = jobs.setdefault(root, {"root": root, "gpus": set(), "pids": {root}, "cwd": r["job_cwd"].get(root, ""),
                                   "cmd": cmd, "name": task_name(cmd)})
        j["gpus"].add(uuid_idx[uuid])
        j["pids"].add(pid)
        j["pids"] |= r["job_pids"].get(root, set())
    r["jobs"] = sorted(jobs.values(), key=lambda j: min(j["gpus"]))
    job_of_card = {i: j for j in r["jobs"] for i in j["gpus"]}
    for g in r["gpus"]:
        g["job"] = job_of_card.get(g["idx"])
        g["owners"] = owners.get(g["idx"], [])
        g["idle"] = not g["owners"] and not g["util"] and (g["used"] or 0) < IDLE_MEM_MIB
    r["gpus"].sort(key=lambda g: g["idx"])
    if r["mem"] and r["mem"][0]:
        total, avail = r["mem"]
        r["mem_pct"] = 100 * (total - avail) / total
    else:
        r["mem_pct"] = None
    return r


def plan(hosts, results):
    """把卡分进各组。返回 [(section, name, [(host, r, err, [gpu])])]，最后是借用组。"""
    by_host = {h: (r, err) for h, r, err in results}
    claimed = {}  # host -> None(整机) | set(idx)
    groups = []
    for g in GROUPS:
        members = []
        for spec in g["cards"]:
            host, idxs = parse_cards(spec)
            prev = claimed.get(host, set())
            claimed[host] = None if idxs is None or prev is None else prev | idxs
            r, err = by_host.get(host, (None, "未探测"))
            gpus = [x for x in r["gpus"] if idxs is None or x["idx"] in idxs] if r else []
            members.append((host, r, err, gpus))
        groups.append((g["section"], g["name"], members))

    borrow = []
    for host in hosts:
        r, err = by_host[host]
        mine = claimed.get(host, set())
        if mine is None or r is None:
            continue
        gpus = [x for x in r["gpus"] if x["idx"] not in mine]
        if gpus:
            borrow.append((host, r, err, gpus))
    groups.append((BORROW, "", borrow))
    return groups


class Table:
    """带框线的表格。行可以比列少：最后一个单元格横跨剩下的列（用于报错 / 无 GPU / CPU 用户）。

    rule 标记行前的分隔线：'full' 贯穿整行，'inner' 从第 2 列开始（第 1 列是合并单元格）。
    """

    def __init__(self, header, st):
        self.header, self.st, self.rows = header, st, []

    def add(self, cells, rule=None):
        self.rows.append((cells, rule))

    def render(self):
        n = len(self.header)
        w = [width(h) for h in self.header]
        for cells, _ in self.rows:
            if len(cells) == n:
                w = [max(a, width(c)) for a, c in zip(w, cells)]
        # 横跨单元格放不下时，把多出来的宽度加到最后一列
        for cells, _ in self.rows:
            k = len(cells) - 1
            need = width(cells[-1]) - (sum(w[k:]) + 3 * (n - 1 - k))
            if need > 0:
                w[-1] += need

        def line(t):
            return self.st(t, "2")

        def rule(left, mid, right, skip_first=False):
            segs = ["─" * (x + 2) for x in w]
            if skip_first:  # 第 1 列是合并单元格，分隔线从第 2 列开始
                return line("│" + " " * len(segs[0]) + "├" + mid.join(segs[1:]) + right)
            return line(left + mid.join(segs) + right)

        def row(cells):
            k = len(cells) - 1
            ws = w[:k] + [sum(w[k:]) + 3 * (n - 1 - k)]
            bar_ = line("│")
            return bar_ + bar_.join(" " + pad(c, x) + " " for c, x in zip(cells, ws)) + bar_

        out = [rule("┌", "┬", "┐"), row([self.st(h, "1") for h in self.header]), rule("├", "┼", "┤")]
        for i, (cells, r) in enumerate(self.rows):
            if i and r:
                out.append(rule("├", "┼", "┤", skip_first=(r == "inner")))
            out.append(row(cells))
        out.append(rule("└", "┴", "┘"))
        return out


def render(hosts, results, args, st):
    for _, r, err in results:
        if not err:
            analyze(r)
    groups = plan(hosts, results)

    cards = {}
    for _, _, members in groups:
        for _, _, _, gpus in members:
            for g in gpus:
                for n in g["owners"]:
                    cards[n] = cards.get(n, 0) + 1
    colors = Colors(cards)

    def task_cell(g, prev):
        j = g["job"]
        if not j:
            return ""
        return st("〃", "2") if prev is j else st(j["name"], "1")

    def card_cells(g, prev=None):
        mem = f"{(g['used'] or 0) / 1024:.0f}/{(g['total'] or 0) / 1024:.0f}G"
        mem_pct = 100 * (g["used"] or 0) / g["total"] if g["total"] else None
        util = f"{g['util']:.0f}%" if g["util"] is not None else "N/A"
        idx = f"{g['idx']:>3}"
        if g["idle"]:
            return [idx, bar(0, BAR_W, st, True) + st(f"{util:>5}", "2"),
                    bar(mem_pct, BAR_W, st, True) + " " + st(f"{mem:>7}", "2"), st("空闲", "1;32"), ""]
        who = ",".join(st(n, colors[n]) for n in (g["owners"] or ["?"]))
        return [idx, bar(g["util"], BAR_W, st) + st.level(f"{util:>5}", g["util"]),
                bar(mem_pct, BAR_W, st) + " " + f"{mem:>7}", who, task_cell(g, prev)]

    def host_rows(host, r, err, gpus):
        """一台主机的若干行（不含第 1 列）。主机列：主机名 / cpu / mem。"""
        if err:
            return [[st(host, "1"), st(f"✗ {err}", "31")]]
        side = [st(host, "1")]
        if r["cpu"] is not None:
            side.append(st(f"cpu {r['cpu']:3.0f}%", "2"))
        if r["mem_pct"] is not None:
            side.append(st(f"mem {r['mem_pct']:3.0f}%", "2"))
        if not r["gpus"]:
            rows = [[st("无 GPU", "2") if not r["has_gpu"] else st("nvidia-smi 无设备", "33")]]
        else:
            rows = [card_cells(g, gpus[i - 1]["job"] if i else None) for i, g in enumerate(gpus)]
        if args.verbose:
            cpu = sorted(((u, c / 100) for u, c in r["cpu_users"].items() if c / 100 >= CPU_USER_MIN_CORES),
                         key=lambda x: -x[1])
            if cpu:
                rows.append([st("CPU 用户  " + "  ".join(f"{u} {c:.1f}c" for u, c in cpu), "2")])
        while len(rows) < len(side):
            rows.append(["", "", "", "", ""])
        return [[side[i] if i < len(side) else ""] + cells for i, cells in enumerate(rows)]

    table = Table(["分组", "主机", "GPU", "利用率", "显存", "用户", "任务"], st)
    free_by = {}
    for section, name, members in groups:
        borrow = section == BORROW
        if borrow and args.free:
            members = [(h, r, e, [g for g in gpus if g["idle"]]) for h, r, e, gpus in members]
            members = [m for m in members if m[3]]
        gs = [g for _, _, _, gpus in members for g in gpus]
        n_free = sum(g["idle"] for g in gs)
        free_by[section] = free_by.get(section, 0) + n_free

        label = [st(name or section, "1")]
        if name:
            label.append(st(section, "2"))
        label.append(st(f"空闲 {n_free}/{len(gs)}", "1;32" if n_free else "2"))
        if borrow and args.free:
            label.append(st("仅空闲", "2"))

        rows = []  # (cells, rule)
        for i, m in enumerate(members):
            for j, cells in enumerate(host_rows(*m)):
                rows.append((cells, "inner" if i and not j else None))
        if not rows:
            rows.append(([st("（无）", "2")], None))
        while len(rows) < len(label):
            rows.append((["", "", "", "", "", ""], None))
        for i, (cells, r) in enumerate(rows):
            table.add([label[i] if i < len(label) else ""] + cells, "full" if i == 0 else r)

    out = table.render() + [""]
    ok = sum(1 for _, _, err in results if not err)
    failed = [(h, err) for h, _, err in results if err]
    free_text = "，".join(f"{sec} {st(str(n), '1;32' if n else '2')}" for sec, n in free_by.items())
    out.append(f"在线 {ok}/{len(results)} 台；空闲 GPU：{free_text} 张")
    by_err = {}
    for h, err in failed:
        by_err.setdefault(re.sub(r"^\S+@\S+?:\s*", "", err).rstrip("."), []).append(h)
    for err, hs in sorted(by_err.items(), key=lambda kv: -len(kv[1])):
        out.append(st(f"✗ {len(hs)} 台 {err}：", "31") + st(host_ranges(hs), "2"))
    return out, bool(failed)


def load_claims():
    """读 arena registry 当前占用（不含 archive/）：host -> [claim]。只要带 gpus 的登记。"""
    claims = {}
    if not ARENA_REGISTRY:
        return claims
    for path in sorted(glob.glob(os.path.join(ARENA_REGISTRY, "*.md"))):
        try:
            with open(path, encoding="utf-8") as fh:
                m = re.match(r"---\n(.*?)\n---", fh.read(), re.S)
        except OSError:
            continue
        if not m:
            continue
        meta = {}
        for ln in m.group(1).splitlines():
            k, sep, v = ln.partition(":")
            if sep:
                meta[k.strip()] = v.strip()
        try:
            gpus = {int(x) for x in meta.get("gpus", "").split(",") if x.strip()}
            expires = datetime.fromisoformat(meta["expires"]) if meta.get("expires") else None
        except ValueError:
            continue
        if gpus and meta.get("host"):
            claims.setdefault(meta["host"], []).append({
                "gpus": gpus, "pid": meta.get("pid", ""), "title": meta.get("title", ""),
                "agent": meta.get("agent", ""), "expires": expires, "resource": meta.get("resource", "")})
    return claims


def wrap(text, w):
    """按显示宽度折行。优先在空格处断，长词（路径）在 / - _ , 之后断，实在不行硬断。"""
    lines, cur = [], ""
    words = []
    for word in re.split(r"(?<= )", text):
        # 选项名和它的取值不拆开：取值太长时在取值内部的 / 处断行
        if words and words[-1].startswith("-") and len(words[-1]) <= 24 and words[-1].endswith(" ") \
                and not words[-1].strip().endswith(("/", ")")) and " " not in words[-1].strip():
            words[-1] += word
        else:
            words.append(word)
    for word in words:
        if width(cur + word) <= w:
            cur += word
            continue
        if cur.strip():
            lines.append(cur.rstrip())
            cur = ""
        while width(word) > w:
            cut, acc = 0, 0
            for i, c in enumerate(word):
                acc += 2 if unicodedata.east_asian_width(c) in "WF" else 1
                if acc > w:
                    break
                if c in "/-_,":
                    cut = i + 1
            cut = cut or max(1, i)
            lines.append(word[:cut])
            word = word[cut:]
        cur = word
    if cur.strip() or not lines:
        lines.append(cur.rstrip())
    return lines


def split_cmd(cmd, cwd):
    """命令行拆成 (解释器, [行])：程序 + 位置参数一行，之后每个 --选项 连同取值一行；
    工作目录下的路径改写成 ./ 相对路径，连续重复的同名选项折叠成一行。"""
    toks = cmd.split()
    if not toks:
        return "", ["?"]
    exe, toks = toks[0], toks[1:]
    if cwd and cwd != "/":
        toks = [t.replace(cwd.rstrip("/") + "/", "./") for t in toks]
    head, opts = [os.path.basename(exe)], []
    for t in toks:
        if t.startswith("--") or (opts and t.startswith("-") and len(t) == 2 and not head[-1:] == ["-m"]):
            opts.append([t])
        elif opts:
            opts[-1].append(t)
        else:
            head.append(t)
    lines = [" ".join(head)]
    i = 0
    while i < len(opts):
        k = i
        while k + 1 < len(opts) and opts[k + 1][0] == opts[i][0]:
            k += 1
        if k - i >= 2:  # 同一选项连续出现 3 次以上：只留第一条，其余计数
            lines.append(" ".join(opts[i]) + f"  （另有 {k - i} 个 {opts[i][0]}）")
        else:
            lines += [" ".join(o) for o in opts[i:k + 1]]
        i = k + 1
    return exe, lines


def render_tasks(hosts, results, args, st):
    """--tasks：每个自己的 GPU 任务一个块，列出工作目录 / 命令 / 解释器 / 对应的 arena 登记。

    登记与任务的对应：pid 精确命中优先；没有命中时退而按卡号重叠，但只认未过期的登记。
    """
    now = datetime.now(timezone.utc)
    claims = load_claims()
    by_host = {h: r for h, r, err in results if not err}
    term = shutil.get_terminal_size((120, 24)).columns if sys.stdout.isatty() else 120
    label_w = 7

    def live(c):
        return not c["expires"] or c["expires"] >= now

    def claim_meta(c):
        bits = [c["agent"]] if c["agent"] else []
        if c["expires"] and not live(c):
            return st(" · ".join(bits + ["已过期"]), "31")
        if c["expires"]:
            bits.append("至 " + c["expires"].astimezone().strftime("%m-%d %H:%M"))
        return st(" · ".join(bits), "32")

    def block(gutter, header, right, fields):
        """header 行 + 若干 (标签, [行], 续行缩进) 字段，左侧一条彩色竖线。"""
        g = st("│", gutter)
        right_w = width(right)
        gap = " " * max(1, term - 3 - width(header) - right_w) if right else ""
        out = [st("╭─ ", gutter) + header + gap + right]
        body_w = max(20, term - 2 - label_w)
        for label, values, hang in fields:
            # 首行顶格，其余（后续取值与折行）统一多缩进 hang 列
            pieces = [p for v in values for p in wrap(v, body_w - hang)]
            for k, piece in enumerate(pieces):
                lead = pad(st(label, "2"), label_w) if k == 0 else " " * (label_w + hang)
                out.append(f"{g} {lead}{piece}")
        out.append(st("╰─", gutter))
        return out

    out, used, tasks = [], set(), []
    for host in hosts:
        r = by_host.get(host)
        if not r:
            continue
        analyze(r)
        hc = claims.get(host, [])
        for j in r["jobs"]:
            hit = [c for c in hc if c["pid"] in j["pids"]] or [c for c in hc if live(c) and c["gpus"] & j["gpus"]]
            used.update(id(c) for c in hit)
            tasks.append((host, j, hit))

    n_gpu = sum(len(j["gpus"]) for _, j, _ in tasks)
    unclaimed = sum(1 for _, _, hit in tasks if not hit)
    orphan = [(h, c) for h in hosts for c in claims.get(h, []) if id(c) not in used and h in by_host]
    alive = [(h, c) for h, c in orphan if live(c)]
    stale = len(orphan) - len(alive)

    summary = [f"自己的 GPU 任务 {st(str(len(tasks)), '1')} 个，共 {st(str(n_gpu), '1')} 卡"]
    if unclaimed:
        summary.append(st(f"{unclaimed} 个未在 arena 登记", "33"))
    if alive:
        summary.append(st(f"{len(alive)} 条登记没见到进程", "33"))
    out += ["，".join(summary), ""]

    for host, j, hit in tasks:
        exe, cmd_lines = split_cmd(j["cmd"], j["cwd"])
        header = st(host, "1") + "  " + st(f"GPU {ranges(j['gpus'])}", "36") + "  " + st(j["name"], "1")
        fields = [("目录", [j["cwd"] or "?"], 0), ("命令", cmd_lines, 2)]
        if exe and "/" in exe:
            fields.append(("环境", [exe], 0))
        if hit:
            for c in hit:
                title = c["title"].replace(j["cwd"].rstrip("/") + "/", "./") if j["cwd"] else c["title"]
                fields.append(("arena", [claim_meta(c), title], 0))
        else:
            fields.append(("arena", [st("未登记", "33")], 0))
        out += block("36" if hit else "33", header, st(f"pid {j['root']}", "2"), fields)
        out.append("")
    if not tasks:
        out += [st("没有自己的 GPU 任务", "2"), ""]

    for h, c in alive:
        header = st(h, "1") + "  " + st(f"GPU {ranges(c['gpus'])}", "36") + "  " + st("登记了但没见到进程", "1;33")
        fields = [("arena", [claim_meta(c), c["title"]], 0), ("释放", [f"arena release {c['resource']}"], 0)]
        out += block("33", header, "", fields)
        out.append("")
    if stale:
        out.append(st(f"arena 中另有 {stale} 条已过期、且对不上任何进程的 GPU 登记，建议 release", "33"))
    failed = [h for h, _, err in results if err]
    return out, bool(failed)


def collect(hosts, args):
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        return list(ex.map(lambda h: probe(h, args.timeout), hosts))


# ---- --wait：等指定的卡全部空出来 ----------------------------------------------------------
#
# 等待期间用 OSC 7501（Program Status Protocol）把所在终端标成 blocked，Rex 等终端因此能把
# 「卡在等 GPU」和「正在干活」区分开。agent 从后台 / 管道里调用时自己没有终端，所以沿进程链
# 往上找最外层那个有终端的祖先：Rex pane 里的 shell（或 docker exec / ssh 进去后的那一层）。
# 不取最近的那个，是因为 Codex 会给命令单独开一个 pty，那个 pty 不通往 Rex。

def outer_tty():
    """沿父进程链往上，返回最外层祖先的终端设备路径；都没有终端则返回 None。"""
    pid, found = os.getpid(), None
    while pid > 1:
        for fd in (0, 1, 2):
            try:
                path = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if path.startswith("/dev/pts/") or path.startswith("/dev/tty"):
                found = path
                break
        try:
            with open(f"/proc/{pid}/stat") as fh:
                # comm 可能含空格和括号，ppid 在最后一个 ')' 之后的第二个字段
                pid = int(fh.read().rpartition(")")[2].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return found


class TermStatus:
    """OSC 7501 子记录 gpu-wait/<pid>。不带 app，沿用根记录（claude-code / codex）的 app。"""

    def __init__(self):
        self.tty = outer_tty()
        self.id = f"gpu-wait/{os.getpid()}"
        self.last = None

    def _send(self, body):
        if not self.tty:
            return
        try:
            with open(self.tty, "w") as fh:
                fh.write(f"\033]7501;{body}\033\\")
        except OSError:
            pass

    def blocked(self, msg):
        # msg 必须是单行、不含控制字符
        msg = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", msg)[:160]
        if msg == self.last:
            return
        self.last = msg
        b64 = lambda t: base64.b64encode(t.encode()).decode()  # noqa: E731
        self._send(f"state=blocked:id={self.id}:title={b64('GPU')}:msg={b64(msg)}")

    def clear(self):
        if self.last is not None:
            self._send(f"state=clear:id={self.id}")
            self.last = None


def busy_cards(specs, args, now):
    """探测一次，返回 [(host, idx, 原因)]：仍被占用的卡；连不上的主机整体算作占用。"""
    want = {}  # host -> None(整机) | set(idx)
    for spec in specs:
        host, idxs = parse_cards(spec)
        prev = want.get(host, set())
        want[host] = None if idxs is None or prev is None else prev | idxs
    claims = {} if args.ignore_arena else load_claims()
    busy = []
    for host, r, err in collect(list(want), args):
        if err:
            busy.append((host, None, f"探测失败：{err}"))
            continue
        analyze(r)
        idxs = want[host]
        gpus = {g["idx"]: g for g in r["gpus"]}
        for i in sorted(gpus if idxs is None else idxs):
            g = gpus.get(i)
            if g is None:
                busy.append((host, i, "没有这张卡"))
            elif not g["idle"]:
                who = ",".join(g["owners"]) or f"显存 {g['used'] or 0:.0f} MiB"
                busy.append((host, i, who))
            else:
                hit = [c for c in claims.get(host, []) if i in c["gpus"] and (not c["expires"] or c["expires"] >= now)]
                if hit:
                    busy.append((host, i, "arena：" + (hit[0]["agent"] or hit[0]["title"] or "已登记")))
    return busy


def describe(busy):
    """[(host, idx, why)] -> 'dgx0011 gpu0-1 (alice), gpu3 (arena：codex)'，按主机、原因合并。"""
    by = {}
    for host, i, why in busy:
        by.setdefault(host, {}).setdefault(why, []).append(i)
    parts = []
    for host, whys in by.items():
        cards = [("整机" if None in idxs else "gpu" + ranges(idxs)) + f"（{why}）" for why, idxs in whys.items()]
        parts.append(host + " " + "，".join(cards))
    return "；".join(parts)


def wait_free(specs, args):
    status = TermStatus()

    def stop(signum, _frame):
        raise SystemExit(128 + signum)

    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    deadline = time.time() + args.max_wait if args.max_wait else None
    try:
        while True:
            busy = busy_cards(specs, args, datetime.now(timezone.utc))
            if not busy:
                print(f"gpu-wait: {' '.join(specs)} 已空闲", file=sys.stderr)
                return 0
            what = describe(busy)
            status.blocked("等待 GPU：" + what)
            print(time.strftime("%H:%M:%S") + f" gpu-wait: 仍被占用 {what}", file=sys.stderr, flush=True)
            if deadline and time.time() + args.interval > deadline:
                print(f"gpu-wait: 等待超过 {args.max_wait:g}s，放弃", file=sys.stderr)
                return 2
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 130
    finally:
        status.clear()


def main():
    ap = argparse.ArgumentParser(description="并发查看一组主机的 GPU（每卡一行，按个人 / 借用分组）与 CPU 使用情况。")
    ap.add_argument("hosts", nargs="*", help=f"要查询的主机（默认：{len(DEFAULT_HOSTS)} 台预设主机 + 分组里的主机）")
    ap.add_argument("-f", "--free", action="store_true", help="借用组只显示空闲卡")
    ap.add_argument("-T", "--tasks", action="store_true", help="改为逐个列出自己的 GPU 任务：完整命令 / 工作目录 / arena 登记")
    ap.add_argument("-v", "--verbose", action="store_true", help="附带每台主机的 CPU 用户")
    ap.add_argument("-w", "--watch", type=float, metavar="SEC", help="每 SEC 秒刷新一次（Ctrl-C 退出）")
    ap.add_argument("-j", "--jobs", type=int, default=32, help="并发 ssh 数（默认 32）")
    ap.add_argument("-t", "--timeout", type=int, default=30, help="单台主机超时秒数（默认 30）")
    ap.add_argument("--no-color", action="store_true", help="关闭颜色")
    wait = ap.add_argument_group("等待模式（gpu-wait）")
    wait.add_argument("--wait", action="store_true",
                      help="把位置参数当作卡（dgx0011 / dgx0011:0-3,6），阻塞到它们全部空闲后返回 0；"
                           "等待期间把终端标成 blocked（OSC 7501）")
    wait.add_argument("-i", "--interval", type=float, default=30, metavar="SEC", help="--wait 的探测间隔（默认 30）")
    wait.add_argument("--max-wait", type=float, metavar="SEC", help="--wait 最多等这么久，超时返回 2")
    wait.add_argument("--ignore-arena", action="store_true", help="--wait 不把 arena 里未过期的登记算作占用")
    args = ap.parse_args()

    if args.wait:
        if not args.hosts:
            ap.error("--wait 需要至少一个卡规格，如 dgx0011:0-7")
        return wait_free(args.hosts, args)

    group_hosts = [parse_cards(c)[0] for g in GROUPS for c in g["cards"]]
    hosts = list(dict.fromkeys(group_hosts + (args.hosts or DEFAULT_HOSTS)))
    if not hosts:
        ap.error("没有预设主机，请在参数中给出主机名")
    st = Style(not args.no_color and sys.stdout.isatty() and "NO_COLOR" not in os.environ)

    if not args.watch:
        if sys.stderr.isatty():
            print(f"正在探测 {len(hosts)} 台主机…", end="\r", file=sys.stderr, flush=True)
        results = collect(hosts, args)
        if sys.stderr.isatty():
            print("\033[2K", end="\r", file=sys.stderr, flush=True)
        lines, failed = (render_tasks if args.tasks else render)(hosts, results, args, st)
        print("\n".join(lines))
        return 1 if failed else 0

    sys.stdout.write("\033[2J")
    try:
        while True:
            t0 = time.time()
            lines, _ = (render_tasks if args.tasks else render)(hosts, collect(hosts, args), args, st)
            stamp = st(time.strftime("%H:%M:%S") + f"  每 {args.watch:g}s 刷新，Ctrl-C 退出", "2")
            # 光标归位后覆盖重画，避免整屏清空带来的闪烁
            sys.stdout.write("\033[H" + "\n".join(ln + "\033[K" for ln in [stamp] + lines) + "\033[J")
            sys.stdout.flush()
            time.sleep(max(0.0, args.watch - (time.time() - t0)))
    except KeyboardInterrupt:
        print()
        return 0


if __name__ == "__main__":
    sys.exit(main())
