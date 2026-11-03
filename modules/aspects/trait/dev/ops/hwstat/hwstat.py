"""hwstat: 并发 ssh 到一组主机，汇总 CPU / 内存 / GPU 使用情况与占用用户。"""

import argparse
import json
import os
import re
import time
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

DEFAULT_HOSTS = json.loads(r"""@HOSTS@""")

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
SPARK = "▁▂▃▄▅▆▇█"
EIGHTHS = " ▏▎▍▌▋▊▉"
# 用户配色（256 色），按区分度从高到低排；刻意避开表示负载等级的红 / 黄 / 绿
PALETTE = ["38;5;33", "38;5;208", "38;5;201", "38;5;51", "38;5;141", "38;5;180", "38;5;217", "38;5;111"]
UNKNOWN = "38;5;250"  # 卡被占用但看不到进程属主（容器内进程等）


def width(s):
    return len(ANSI.sub("", s))


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
        fmt = [("-".join(f"{int(x):0{w}d}" for x in p.split("-"))) for p in parts]
        out.append(key + ",".join(fmt))
    return " ".join(out)


def bar(pct, n, st):
    """水平条：n 格宽，1/8 格精度，空余部分是暗色轨道。"""
    if pct is None:
        return st("?".ljust(n), "2")
    eighths = round(max(0.0, min(pct, 100.0)) / 100 * n * 8)
    full, rem = divmod(eighths, 8)
    filled = "█" * full + (EIGHTHS[rem] if rem else "")
    return st.level(filled, pct) + st("░" * (n - len(filled)), "2")


def spark(frac):
    return SPARK[max(0, min(len(SPARK) - 1, int(frac * len(SPARK) - 1e-9)))]


class Colors:
    """用户 -> 颜色。占卡多的用户先挑色，保证同屏最显眼的几位颜色互相区分最大。"""

    def __init__(self, cards):
        order = sorted(cards, key=lambda n: (-cards[n], n))
        self.map = {n: PALETTE[i % len(PALETTE)] for i, n in enumerate(n for n in order if n != "?")}

    def __getitem__(self, name):
        return self.map.get(name, UNKNOWN)


def analyze(r):
    """整理成渲染需要的结构：每张卡的占用者、空闲卡、GPU 用户。"""
    uuid_idx = {g["uuid"]: g["idx"] for g in r["gpus"]}
    owners = {}  # idx -> [user]
    for uuid, pid in r["apps"]:
        idx = uuid_idx.get(uuid)
        if idx is None:
            continue
        name = r["pid_user"].get(pid, "?")
        if name not in owners.setdefault(idx, []):
            owners[idx].append(name)
    gpus = sorted(r["gpus"], key=lambda g: g["idx"])
    idle = [g["idx"] for g in gpus
            if g["idx"] not in owners and not g["util"] and (g["used"] or 0) < IDLE_MEM_MIB]
    gpu_users = {}
    for idx, names in owners.items():
        for n in names:
            gpu_users.setdefault(n, set()).add(idx)
    r.update(gpus=gpus, owners=owners, idle=idle, gpu_users=gpu_users)
    if r["mem"] and r["mem"][0]:
        total, avail = r["mem"]
        r["mem_pct"] = 100 * (total - avail) / total
    else:
        r["mem_pct"] = None
    return r


def gpu_cells(r, st, colors):
    """每张卡两个字形：利用率高度 + 显存高度，颜色 = 占用者；空闲卡是暗色 ··。"""
    cells = []
    for g in r["gpus"]:
        if g["idx"] in r["idle"]:
            cells.append(st("··", "2"))
            continue
        names = r["owners"].get(g["idx"], ["?"])
        color = colors[names[0]]
        if len(names) > 1:
            color += ";4"  # 多人共用一张卡：加下划线
        u = spark((g["util"] or 0) / 100)
        m = spark((g["used"] or 0) / g["total"]) if g["total"] else "?"
        cells.append(st(u + m, color))
    return cells


def detail_lines(r, st, colors):
    """-v：逐卡文字明细 + CPU 用户。"""
    lines = []
    for g in r["gpus"]:
        if g["idx"] in r["idle"]:
            continue
        names = r["owners"].get(g["idx"], ["?"])
        util = f"{g['util']:.0f}%" if g["util"] is not None else "N/A"
        mem = f"{(g['used'] or 0) / 1024:.0f}/{(g['total'] or 0) / 1024:.0f}G"
        who = " ".join(st(n, colors[n]) for n in names)
        lines.append(f"GPU{g['idx']} {util:>4} {mem:>8}  {who}")
    cpu = [(u, c / 100) for u, c in r["cpu_users"].items() if c / 100 >= CPU_USER_MIN_CORES]
    if cpu:
        cpu.sort(key=lambda x: -x[1])
        lines.append("CPU  " + "  ".join(f"{u} {c:.1f}c" for u, c in cpu))
    return lines


def render(results, args, st):
    ok = [(h, analyze(r)) for h, r, err in results if not err]
    failed = [(h, err) for h, _, err in results if err]
    cards = {}
    for _, r in ok:
        for n, ix in r["gpu_users"].items():
            cards[n] = cards.get(n, 0) + len(ix)
    colors = Colors(cards)

    hw = max([4] + [len(h) for h, _ in ok])
    ncard = max([0] + [len(r["gpus"]) for _, r in ok])
    gpu_w = max(3 * ncard - 1, 3)
    bw = 8
    out = []

    gpu_head = " ".join(f"{i:<2}" for i in range(ncard)) if ncard else "GPU"
    head = "  ".join([pad("HOST", hw), pad("CPU", bw + 5), pad("MEM", bw + 5), pad(gpu_head, gpu_w), "FREE  USERS"])
    out.append(st(head.rstrip(), "1"))

    idle_total = 0
    for host, r in ok:
        cpu = bar(r["cpu"], bw, st) + f"{r['cpu']:4.0f}%" if r["cpu"] is not None else pad("?", bw + 5)
        mem = bar(r["mem_pct"], bw, st) + f"{r['mem_pct']:4.0f}%" if r["mem_pct"] is not None else pad("?", bw + 5)
        if r["gpus"]:
            gpus = " ".join(gpu_cells(r, st, colors))
            n_idle = len(r["idle"])
            idle_total += n_idle
            free = st(f"{n_idle}/{len(r['gpus'])}", "1;32" if n_idle else "2")
        else:
            gpus = st("无 GPU", "2") if not r["has_gpu"] else st("nvidia-smi 无设备", "33")
            free = ""
        users = sorted(r["gpu_users"].items(), key=lambda kv: (-len(kv[1]), kv[0]))
        utext = "  ".join(st(n, colors[n]) + " " + st(ranges(ix), "2") for n, ix in users)
        line = "  ".join([pad(host, hw), cpu, mem, pad(gpus, gpu_w), pad(free, 4), utext])
        out.append(line.rstrip())
        if args.verbose:
            out.extend(" " * (hw + 2) + st("│ ", "2") + ln for ln in detail_lines(r, st, colors))

    out.append("")
    summary = f"在线 {len(ok)}/{len(results)} 台，空闲 GPU {st(str(idle_total), '1;32')} 张"
    legend = "每卡两格 = 利用率 / 显存（▁→█），颜色 = 用户，下划线 = 多人共用，·· = 空闲"
    out.append(summary)
    out.append(st(legend, "2"))
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
    ap = argparse.ArgumentParser(description="并发查看一组主机的 CPU / GPU 使用情况与占用用户。")
    ap.add_argument("hosts", nargs="*", help=f"要查询的主机（默认：{len(DEFAULT_HOSTS)} 台预设主机）")
    ap.add_argument("-v", "--verbose", action="store_true", help="逐卡列出利用率 / 显存 / 用户，以及 CPU 用户")
    ap.add_argument("-w", "--watch", type=float, metavar="SEC", help="每 SEC 秒刷新一次（Ctrl-C 退出）")
    ap.add_argument("-j", "--jobs", type=int, default=32, help="并发 ssh 数（默认 32）")
    ap.add_argument("-t", "--timeout", type=int, default=30, help="单台主机超时秒数（默认 30）")
    ap.add_argument("--no-color", action="store_true", help="关闭颜色")
    args = ap.parse_args()

    hosts = args.hosts or DEFAULT_HOSTS
    if not hosts:
        ap.error("没有预设主机，请在参数中给出主机名")
    st = Style(not args.no_color and sys.stdout.isatty() and "NO_COLOR" not in os.environ)

    if not args.watch:
        if sys.stderr.isatty():
            print(f"正在探测 {len(hosts)} 台主机…", end="\r", file=sys.stderr, flush=True)
        results = collect(hosts, args)
        if sys.stderr.isatty():
            print("\033[2K", end="\r", file=sys.stderr, flush=True)
        lines, failed = render(results, args, st)
        print("\n".join(lines))
        return 1 if failed else 0

    sys.stdout.write("\033[2J")
    try:
        while True:
            t0 = time.time()
            lines, _ = render(collect(hosts, args), args, st)
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
