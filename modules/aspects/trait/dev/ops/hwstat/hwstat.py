"""hwstat: 并发 ssh 到一组主机，汇总 CPU / 内存 / GPU 使用情况与占用用户。"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor

DEFAULT_HOSTS = json.loads(r"""@HOSTS@""")
GROUPS = json.loads(r"""@GROUPS@""")

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
         "cpu_users": {}, "gpus": [], "apps": [], "pid_user": {}, "has_gpu": True}
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
    for g in r["gpus"]:
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

    def card_cells(g):
        mem = f"{(g['used'] or 0) / 1024:.0f}/{(g['total'] or 0) / 1024:.0f}G"
        mem_pct = 100 * (g["used"] or 0) / g["total"] if g["total"] else None
        util = f"{g['util']:.0f}%" if g["util"] is not None else "N/A"
        idx = f"{g['idx']:>3}"
        if g["idle"]:
            return [idx, bar(0, BAR_W, st, True) + st(f"{util:>5}", "2"),
                    bar(mem_pct, BAR_W, st, True) + " " + st(f"{mem:>7}", "2"), st("空闲", "1;32")]
        who = ",".join(st(n, colors[n]) for n in (g["owners"] or ["?"]))
        return [idx, bar(g["util"], BAR_W, st) + st.level(f"{util:>5}", g["util"]),
                bar(mem_pct, BAR_W, st) + " " + f"{mem:>7}", who]

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
            rows = [card_cells(g) for g in gpus]
        if args.verbose:
            cpu = sorted(((u, c / 100) for u, c in r["cpu_users"].items() if c / 100 >= CPU_USER_MIN_CORES),
                         key=lambda x: -x[1])
            if cpu:
                rows.append([st("CPU 用户  " + "  ".join(f"{u} {c:.1f}c" for u, c in cpu), "2")])
        while len(rows) < len(side):
            rows.append(["", "", "", ""])
        return [[side[i] if i < len(side) else ""] + cells for i, cells in enumerate(rows)]

    table = Table(["分组", "主机", "GPU", "利用率", "显存", "用户"], st)
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
            rows.append((["", "", "", "", ""], None))
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


def collect(hosts, args):
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        return list(ex.map(lambda h: probe(h, args.timeout), hosts))


def main():
    ap = argparse.ArgumentParser(description="并发查看一组主机的 GPU（每卡一行，按个人 / 借用分组）与 CPU 使用情况。")
    ap.add_argument("hosts", nargs="*", help=f"要查询的主机（默认：{len(DEFAULT_HOSTS)} 台预设主机 + 分组里的主机）")
    ap.add_argument("-f", "--free", action="store_true", help="借用组只显示空闲卡")
    ap.add_argument("-v", "--verbose", action="store_true", help="附带每台主机的 CPU 用户")
    ap.add_argument("-w", "--watch", type=float, metavar="SEC", help="每 SEC 秒刷新一次（Ctrl-C 退出）")
    ap.add_argument("-j", "--jobs", type=int, default=32, help="并发 ssh 数（默认 32）")
    ap.add_argument("-t", "--timeout", type=int, default=30, help="单台主机超时秒数（默认 30）")
    ap.add_argument("--no-color", action="store_true", help="关闭颜色")
    args = ap.parse_args()

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
        lines, failed = render(hosts, results, args, st)
        print("\n".join(lines))
        return 1 if failed else 0

    sys.stdout.write("\033[2J")
    try:
        while True:
            t0 = time.time()
            lines, _ = render(hosts, collect(hosts, args), args, st)
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
