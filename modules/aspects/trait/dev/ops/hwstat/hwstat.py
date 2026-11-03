"""hwstat: 并发 ssh 到一组主机，汇总 CPU / 内存 / GPU 使用情况与占用用户。"""

import argparse
import json
import os
import re
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
# 用户 CPU 占用低于此核数不显示，过滤噪声
CPU_USER_MIN_CORES = 0.5
SPARK = "▁▂▃▄▅▆▇█"


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


def gib(b):
    return f"{b / 2**30:.0f}"


def summarize(r, st):
    """返回 (cells, users_text, idle_gpus)"""
    cpu = r["cpu"]
    cpu_cell = st.level(f"{cpu:3.0f}%" if cpu is not None else "  ?", cpu) + f"/{r['nproc']}c"
    load_cell = f"{r['load']:.1f}" if r["load"] is not None else "?"
    if r["mem"]:
        total, avail = r["mem"]
        pct = 100 * (total - avail) / total if total else None
        mem_cell = st.level(f"{gib(total - avail)}/{gib(total)}G", pct)
    else:
        mem_cell = "?"

    uuid_idx = {g["uuid"]: g["idx"] for g in r["gpus"]}
    gpu_users = {}
    busy = set()
    for uuid, pid in r["apps"]:
        idx = uuid_idx.get(uuid)
        if idx is None:
            continue
        busy.add(idx)
        gpu_users.setdefault(r["pid_user"].get(pid, "?"), set()).add(idx)

    gpus = sorted(r["gpus"], key=lambda g: g["idx"])
    if gpus:
        utils = [g["util"] or 0 for g in gpus]
        avg = sum(utils) / len(utils)
        spark = "".join(st.level(SPARK[min(int(u / 100 * len(SPARK)), len(SPARK) - 1)], u)
                        for u in utils)
        idle = [g["idx"] for g in gpus
                if g["idx"] not in busy and not g["util"] and (g["used"] or 0) < IDLE_MEM_MIB]
        used = sum(g["used"] or 0 for g in gpus) / 1024
        total = sum(g["total"] or 0 for g in gpus) / 1024
        gpu_cell = st.level(f"{avg:3.0f}%", avg) + f" {spark}"
        free_cell = st(f"{len(idle)}/{len(gpus)}", "1;32" if idle else "2")
        gmem_cell = st.level(f"{used:.0f}/{total:.0f}G", 100 * used / total if total else None)
    else:
        idle = []
        # 有 nvidia-smi 但查不到设备：驱动 / 容器透传异常，值得注意
        gpu_cell = st("无 GPU", "2") if not r["has_gpu"] else st("nvidia-smi 无设备", "33")
        free_cell = gmem_cell = ""

    users = []
    names = set(gpu_users) | {u for u, c in r["cpu_users"].items() if c / 100 >= CPU_USER_MIN_CORES}
    # GPU 占用多的排前，其次按 CPU
    for name in sorted(names, key=lambda u: (-len(gpu_users.get(u, ())), -r["cpu_users"].get(u, 0))):
        parts = []
        if name in gpu_users:
            parts.append(f"GPU {ranges(gpu_users[name])}")
        cores = r["cpu_users"].get(name, 0) / 100
        if cores >= CPU_USER_MIN_CORES:
            parts.append(f"{cores:.1f}c")
        users.append(f"{st(name, '1')}({' '.join(parts)})")
    return [cpu_cell, load_cell, mem_cell, gpu_cell, free_cell, gmem_cell], " ".join(users), idle


ANSI = re.compile(r"\033\[[0-9;]*m")


def width(s):
    return len(ANSI.sub("", s))


def pad(s, w):
    return s + " " * (w - width(s))


def main():
    ap = argparse.ArgumentParser(description="并发查看一组主机的 CPU / GPU 使用情况与占用用户。")
    ap.add_argument("hosts", nargs="*", help=f"要查询的主机（默认：{len(DEFAULT_HOSTS)} 台预设主机）")
    ap.add_argument("-j", "--jobs", type=int, default=32, help="并发 ssh 数（默认 32）")
    ap.add_argument("-t", "--timeout", type=int, default=30, help="单台主机超时秒数（默认 30）")
    ap.add_argument("--no-color", action="store_true", help="关闭颜色")
    args = ap.parse_args()

    hosts = args.hosts or DEFAULT_HOSTS
    if not hosts:
        ap.error("没有预设主机，请在参数中给出主机名")
    st = Style(not args.no_color and sys.stdout.isatty() and "NO_COLOR" not in os.environ)

    if sys.stderr.isatty():
        print(f"正在探测 {len(hosts)} 台主机…", end="\r", file=sys.stderr, flush=True)
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        results = list(ex.map(lambda h: probe(h, args.timeout), hosts))
    if sys.stderr.isatty():
        print(" " * 40, end="\r", file=sys.stderr, flush=True)

    header = ["HOST", "CPU", "LOAD", "MEM", "GPU UTIL", "FREE", "GPU MEM", "USERS"]
    rows, failed, idle_total = [], [], []
    for host, r, err in results:
        if err:
            rows.append((host, None, err))
            failed.append(host)
        else:
            cells, users, idle = summarize(r, st)
            rows.append((host, cells, users))
            if idle:
                idle_total.append((host, idle))

    ok_rows = [c for _, c, _ in rows if c]
    widths = [max([len(header[0])] + [len(h) for h, _, _ in rows])]
    for i in range(6):
        widths.append(max([len(header[i + 1])] + [width(c[i]) for c in ok_rows]))

    sep = "  "
    print(st(sep.join(pad(h, w) for h, w in zip(header, widths + [0])).rstrip(), "1;4"))
    for host, cells, tail in rows:
        if cells is None:
            print(pad(host, widths[0]) + sep + st(f"✗ {tail}", "31"))
        else:
            line = sep.join(pad(c, w) for c, w in zip([host] + cells, widths))
            print((line + sep + tail).rstrip())

    n_idle = sum(len(i) for _, i in idle_total)
    print()
    summary = f"可连接 {len(hosts) - len(failed)}/{len(hosts)}"
    if failed:
        summary += st(f"，失败 {len(failed)}", "31")
    summary += f"；空闲 GPU 共 {st(str(n_idle), '1;32')} 张"
    if idle_total:
        summary += "：" + "  ".join(f"{h}[{ranges(i)}]" for h, i in idle_total)
    print(summary)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
