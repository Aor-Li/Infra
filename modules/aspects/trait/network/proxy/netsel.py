"""netsel：在终端里查看 Clash 分流状态、测速、切换节点。

    netsel                 总览：各分流线的当前出口、订阅状态、连通性（会先测一轮延迟）
    netsel -n              总览，但不重新测速（用 mihomo 上次的结果）
    netsel fix             网络不好用时一键修：update，再 tune 所有分流线，最后显示总览
    netsel pick [组]       用 fzf 选择某个分组的出口；不带组名先选组
    netsel tune [线]       按需给分流线调出口（不带线名则全部），只在当前出口不通或明显更差时才换：
                             国内 / 国外 / AI  逐个候选实测该线的目标站；默认的自动组可用就用它，
                                               不可用时钉到实测最好的候选（AI 只会在 AI 自动与
                                               AI 备用之间选，其余候选可能从香港出去，不自动选）
                             TurboAI           实测 philoai.xyz，国外明显快过直连才走国外，否则直连
                                               （ssh 网关经 ssh-direct 绕开 Clash，不受这条线影响）
    netsel update          重新拉取所有订阅；直连拉不下来的，依次借各订阅的节点重试
    netsel setup           把 Clash Verge 收敛到仓库的配置：导入清单里缺的订阅、分流脚本、
                           外部控制器；有差异且 Verge 在运行时会重启它（断网几秒）
    netsel setup --check   只列出待应用的变更，不做任何改动（switch 时由 activation 执行）

switch 不会改动代理：网络只在你执行 `netsel setup` 时才会变。不一致时 switch 与 `netsel`
总览都会提示。

分组结构由 clash-script.js 决定；这里只认组名，不重复定义策略。
订阅有哪些、什么顺序由 sops 下发的订阅清单决定（见 load_subs），不看 Verge 里导入了什么。
"""

import concurrent.futures as cf
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

import yaml

VERGE = os.path.expanduser(
    "~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
)
TEMPLATE = "@template@"
SUBSCRIPTIONS = "@subscriptions@"  # sops 解密后的订阅清单
TEST_URL = "https://www.gstatic.com/generate_204"
# AI 线的健康检查，与 clash-script.js 的同名常量一致（mihomo 按 URL 字符串区分测速记录）：
# 不带 key 访问 Anthropic API，连得上时返回 401。分辨不了地区（香港节点也返回 401）
AI_TEST = "https://api.anthropic.com/v1/models"
AI_EXPECT = "401"
AI_TIMEOUT = 5000  # 毫秒，见 retest_groups
# AI 线的真实出口地区：claude.ai 落在 AI 线（GEOSITE category-ai-!cn），Cloudflare 的 trace 回显出口 loc。
# 节点名不可靠——机场会把 AI 流量另行转发（实测 Forest 的香港节点访问 claude.ai 从美国出去）
AI_TRACE = "https://claude.ai/cdn-cgi/trace"
AI_BLOCKED_LOC = {"HK", "MO", "CN", "RU"}  # 与 clash-script.js 的 AI_BLOCKED 一致
ROUTE = "订阅更新"  # mihomo 拉订阅走的组，见 clash-script.js
LINES = ["TurboAI", "国内", "国外", "AI"]  # 分流线，顺序即展示顺序
# 按 HTTP 实测连通性的分流线 → (目标 URL, 期望状态码)。顺序即 tune 的顺序：TurboAI 的候选里有
# 「国外」，要等它先调好。philoai.xyz 未登录时 302 到飞书登录页，不限状态码
HTTP_LINES = {
    "国内": ("https://www.baidu.com", None),
    "国外": (TEST_URL, None),
    "AI": (AI_TEST, AI_EXPECT),
    "TurboAI": ("https://philoai.xyz", None),
}
# tune 按实测速度选的线：别的候选明显快过默认候选才用别的，差不多就回到默认。其余线的默认候选
# 是自动组（或国内的 DIRECT），通就用它；TurboAI 的默认 DIRECT 不会容灾，直连跨境慢时也「通」
# （gitlab 实测 15–30 KiB/s），只看通不通会一直停在直连
BY_SPEED = {"TurboAI"}
# tune 只会自动切到这些候选（不在表里的线不限）。AI 备用是清单里标了 ai: true 的订阅，出口实测过；
# AI 的其余候选（国外、各订阅）可能从香港出去，测速又分辨不了地区，只能由你用 `netsel pick AI` 手动选
TUNE_ONLY = {"AI": ["AI 自动", "AI 备用"]}
# 总览里另测 ssh 登录的分流线 → ssh 别名（来自对应 home entity 的 provides.ssh，经 SOPS 解密）。
# 只展示不调：TurboAI-gw 经 ssh-direct 绕开 Clash，出口选什么都影响不到它
GATEWAY_SSH = {"TurboAI": "TurboAI-gw"}
SSH = "/usr/bin/ssh"  # activation 的 PATH 里没有 ssh

TTY = sys.stdout.isatty()


def c(code, s):
    return f"\033[{code}m{s}\033[0m" if TTY and code else s


def delay_seg(d, good=200, slow=500, fail="超时"):
    """毫秒 → (文本, 颜色)：1 秒以上写成 1.9s。"""
    if not d:
        return fail, "31"
    return (f"{d}ms" if d < 1000 else f"{d / 1000:.1f}s"), "32" if d < good else "33" if d < slow else "31"


def fmt_delay(d, good=200, slow=500, fail="超时"):
    text, code = delay_seg(d, good, slow, fail)
    return c(code, text)


# ---------------------------------------------------------------- 排版
#
# 终端里按显示宽度对齐：CJK 占两格，ANSI 转义不占格。可截断的单元格写成 [(文本, 颜色)] 段落，
# 先按纯文本截断再上色，免得把转义序列截成两半。

ANSI = re.compile(r"\033\[[0-9;]*m")
OK, BAD, NA = c("32", "✓"), c("31", "✗"), c("2", "·")


def width(s):
    w = 0
    for ch in ANSI.sub("", s):
        if unicodedata.combining(ch) or ch in "‍️":
            continue
        w += 2 if unicodedata.east_asian_width(ch) in "WF" else 1
    return w


def pad(s, w, right=False):
    gap = " " * max(0, w - width(s))
    return gap + s if right else s + gap


def seg_width(segs):
    return sum(width(t) for t, _ in segs)


def clip(segs, maxw):
    """拼接 [(文本, 颜色)]，超过 maxw 时截断并以 … 结尾。"""
    if seg_width(segs) <= maxw:
        return "".join(c(code, t) for t, code in segs)
    out, room = [], maxw - 1
    for t, code in segs:
        keep = ""
        for ch in t:
            if width(keep + ch) > room:
                break
            keep += ch
        room -= width(keep)
        out.append(c(code, keep))
        if keep != t:
            break
    return "".join(out) + "…"


def term_width():
    return shutil.get_terminal_size((100, 24)).columns


def table(rows, right=(), flex=None, maxw=None):
    """对齐成若干行文本。单元格是字符串或段落；right 里的列右对齐；总宽超过 maxw 时截断 flex 列。"""
    def cw(cell):
        return seg_width(cell) if isinstance(cell, list) else width(cell)

    ncol = max(len(r) for r in rows)
    widths = [max((cw(r[i]) for r in rows if i < len(r)), default=0) for i in range(ncol)]
    if flex is not None and maxw:
        over = sum(widths) + 2 * (ncol - 1) - maxw
        if over > 0:
            widths[flex] = max(8, widths[flex] - over)
    out = []
    for r in rows:
        cells = [
            pad(clip(cell, widths[i]) if isinstance(cell, list) else cell, widths[i], i in right)
            for i, cell in enumerate(r)
        ]
        out.append("  ".join(cells).rstrip())
    return out


def box(title, lines, inner=0):
    """圆角框：╭─ 标题 ─╮ … ╰─╯。lines 的宽度由调用方控制在 term_width() - 4 以内；
    inner 给定时至少撑到这么宽，用来让上下几个框对齐。"""
    inner = max([width(ln) for ln in lines] + [width(title) + 1, inner])
    print(c("2", "╭─ ") + c("1", title) + c("2", " " + "─" * (inner - width(title) - 1) + "╮"))
    for ln in lines:
        print(c("2", "│ ") + pad(ln, inner) + c("2", " │"))
    print(c("2", "╰" + "─" * (inner + 2) + "╯"))


def hops(names):
    """出口链的展示段落：中间的分组变暗，末端的节点正常显示。"""
    names = [{"DIRECT": "直连", "REJECT": "拒绝"}.get(n, short(n)) for n in names]
    segs = []
    for i, n in enumerate(names):
        last = i == len(names) - 1
        segs.append((n, None if last else "2"))
        if not last:
            segs.append((" › ", "2"))
    return segs


def warn(msg):
    print(c("33", f" ! {msg}"))


def die(msg):
    print(c("31", f"netsel: {msg}"), file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------- mihomo API


class Api:
    def __init__(self):
        path = os.path.join(VERGE, "clash-verge.yaml")
        if "NETSEL_CONTROLLER" in os.environ:  # 调试用：指向另一个 mihomo 实例
            conf = {
                "external-controller": os.environ["NETSEL_CONTROLLER"],
                "secret": os.environ.get("NETSEL_SECRET", ""),
            }
        else:
            try:
                with open(path) as f:
                    conf = yaml.safe_load(f) or {}
            except OSError:
                die(f"读不到 {path}，Clash Verge 装了吗？")
        ctl = conf.get("external-controller") or ""
        if not ctl:
            die(
                "Clash Verge 没开外部控制器：设置 → Clash 设置 → 外部控制 打开"
                "（默认 127.0.0.1:9097），再重试。"
            )
        if ctl.startswith(":"):
            ctl = "127.0.0.1" + ctl
        self.base = f"http://{ctl.replace('0.0.0.0', '127.0.0.1')}"
        self.secret = conf.get("secret") or ""
        # 控制器在本机，别让环境里的 http_proxy 把请求绕回 Clash
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def call(self, method, path, body=None, timeout=15):
        req = urllib.request.Request(
            self.base + path,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": f"Bearer {self.secret}"},
        )
        try:
            with self.opener.open(req, timeout=timeout) as r:
                data = r.read()
        except urllib.error.HTTPError as e:
            if e.code == 401:
                die("控制器鉴权失败：clash-verge.yaml 里的 secret 与运行中的不一致。")
            raise
        except urllib.error.URLError as e:
            die(f"连不上 mihomo 控制器 {self.base}（{e.reason}），Clash Verge 在运行吗？")
        return json.loads(data) if data else None

    def proxies(self):
        """分组与内置出口（/proxies）加上各订阅的节点——后者只出现在 /providers/proxies。"""
        out = self.call("GET", "/proxies")["proxies"]
        for p in self.providers().values():
            for node in p.get("proxies") or []:
                out.setdefault(node["name"], node)
        return out

    def providers(self):
        return self.call("GET", "/providers/proxies")["providers"]

    def group_delay(self, group, url=TEST_URL, expected=None, timeout_ms=3000):
        """url / expected 要与组自己的健康检查一致，测完 mihomo 才会按新结果重选。"""
        q = urllib.parse.urlencode(
            {"url": url, "timeout": timeout_ms, **({"expected": expected} if expected else {})}
        )
        try:
            return self.call(
                "GET", f"/group/{urllib.parse.quote(group)}/delay?{q}", timeout=30
            )
        except urllib.error.HTTPError:
            return {}  # 整组全挂时 mihomo 返回 503

    def delay(self, name, url, expected=None, timeout_ms=5000):
        q = urllib.parse.urlencode(
            {"url": url, "timeout": timeout_ms, **({"expected": expected} if expected else {})}
        )
        try:
            r = self.call("GET", f"/proxies/{urllib.parse.quote(name)}/delay?{q}")
            return r.get("delay")
        except urllib.error.HTTPError:
            return None

    def select(self, group, name):
        self.call("PUT", f"/proxies/{urllib.parse.quote(group)}", {"name": name})

    def ai_exit(self):
        """AI 线当前的出口地区（如 US），测不出来时为 None。显式经 Clash 的代理端口访问，
        不依赖本机开没开 TUN / 系统代理；请求按规则落在 AI 线。"""
        try:
            conf = self.call("GET", "/configs") or {}
            port = conf.get("mixed-port") or conf.get("port")
            if not port:
                return None
            proxy = f"http://127.0.0.1:{port}"
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
            with opener.open(AI_TRACE, timeout=8) as r:
                text = r.read().decode()
        except (OSError, ValueError):
            return None
        return dict(ln.split("=", 1) for ln in text.splitlines() if "=" in ln).get("loc")


def last_delay(p):
    h = p.get("history") or []
    return h[-1]["delay"] if h else None


def short(name):
    """JMS-1265282@c12s1.portablesubmarines.com:7396 → c12s1:7396"""
    return re.sub(r"^JMS-\d+@([^.]+)\.[^:]+", r"\1", name)


def progress(on, what="测速"):
    if TTY:
        print(c("2", f" {what}中…") + "\r" if on else "\r\033[K", end="", flush=True)


def chain(proxies, name):
    """沿 now 一路展开到具体节点：国外 → 自动容灾 → Forest 自动 → 🇯🇵 JP-…"""
    out = [name]
    while True:
        p = proxies.get(out[-1]) or {}
        nxt = p.get("now")
        if not nxt or nxt in out:
            return out
        out.append(nxt)


def subs(proxies):
    """当前配置里的订阅分组（Forest / JMS …），由 setup 生成的结构推出来。"""
    fallback = proxies.get("自动容灾") or {}
    return [n.removesuffix(" 自动") for n in fallback.get("all", [])]


def provider_key(group):
    """订阅分组名 → provider 名（mihomo 里两者不能重名，见 clash-script.js）。"""
    return group.lower()


def load_subs(wait_s=0):
    """订阅清单：entity/users/aor/secrets.yaml 的 clash.subscriptions，经 sops 解密到本机。

    内容是 YAML 列表 [{name, url, summary?, ai?}]，顺序即「自动容灾」的优先级；恰好一项
    summary: true，它是全局脚本改写的汇总订阅，其余订阅激活时保留原生节点供救急。
    ai: true 的订阅单独成「AI 备用」一档（见 clash-script.js）。
    清单在所有机器上一致，所以分流结构不再取决于本机 Verge 里恰好导入了哪些订阅。"""
    if wait_s:  # 第一次 switch 时 sops-nix 的 launchd agent 与 activation 并行，等它解密
        wait(lambda: os.path.exists(SUBSCRIPTIONS), wait_s)
    text = read(SUBSCRIPTIONS)
    if text is None:
        die(f"读不到订阅清单 {SUBSCRIPTIONS}：sops 没解密？本机需要 ~/.config/sops/age/keys.txt。")
    out = []
    for s in yaml.safe_load(text) or []:
        if not s.get("name") or not s.get("url"):
            die("订阅清单的每一项都要有 name 与 url。")
        out.append({
            "name": s["name"],
            "key": provider_key(s["name"]),
            "url": s["url"],
            "summary": bool(s.get("summary")),
            "ai": bool(s.get("ai")),
        })
    if sum(s["summary"] for s in out) != 1:
        die("订阅清单里要恰好一项 summary: true（汇总订阅）。")
    return out


# ---------------------------------------------------------------- 命令


def cmd_status(api, retest=True):
    hint = drift_hint()
    proxies = api.proxies()
    if not all(line in proxies for line in LINES):
        if hint:  # 脚本还是旧的（分流线改过名），提示里已经让执行 setup
            warn(hint)
            die("当前分流结构与仓库不一致，执行 `netsel setup`。")
        summary = next((s["name"] for s in load_subs() if s["summary"]), "汇总订阅") if os.path.exists(SUBSCRIPTIONS) else "汇总订阅"
        die(f"当前激活的不是汇总订阅，没有 netsel 分流：在 Clash Verge 里选中 {summary}"
            "（deep link 导入新订阅后 Verge 可能自动切到了它），或执行 `netsel setup`。")
    names = subs(proxies)
    if hint:
        warn(hint)

    if retest:
        retest_groups(api, proxies)
        proxies = api.proxies()

    # 连通性：分流线逐条实测（经 mihomo 的出口），GATEWAY_SSH 另测真实 ssh 登录，AI 另查真实出口地区
    progress(True, "实测各分流线")
    with cf.ThreadPoolExecutor() as ex:
        futs = {k: ex.submit(api.delay, k, u, e) for k, (u, e) in HTTP_LINES.items()}
        ssh_futs = {k: ex.submit(probe_ssh, h) for k, h in GATEWAY_SSH.items()}
        loc_fut = ex.submit(api.ai_exit)
        reach = {k: f.result() for k, f in futs.items()}
        ssh_res = {k: f.result() for k, f in ssh_futs.items()}
        loc = loc_fut.result()
    progress(False)

    maxw = term_width() - 4
    rows, broken, gw_down = [], [], []
    for line in LINES:
        ms = reach[line]
        ok = bool(ms)
        target = re.sub(r"^(www|api)\.", "", HTTP_LINES[line][0].split("/")[2])
        val, extra = fmt_delay(ms), ""
        if line in GATEWAY_SSH and ssh_res[line][0] is not None:
            gw_ok, via, gw_ms = ssh_res[line]
            extra = c("2", f"ssh {GATEWAY_SSH[line]}（{via}）") + " " + fmt_delay(gw_ms, 3000, 6000, "失败")
            if not gw_ok:
                gw_down.append(f"ssh {GATEWAY_SSH[line]}（{via}）")
        if line == "AI":
            extra = c("31" if loc in AI_BLOCKED_LOC else "2", f"出口 {loc or '?'}")
            ok = ok and loc not in AI_BLOCKED_LOC
        if ok is False:
            broken.append(line)
        mark = NA if ok is None else OK if ok else BAD
        rows.append([f"{mark} {c('1', line)}", hops(chain(proxies, line)[1:]), c("2", target), val, extra])
    line_box = table(rows, right={3}, flex=1, maxw=maxw)

    provs = api.providers()
    rows, tops = [], []
    for n in names:
        p = provs.get(provider_key(n)) or {}
        nodes = p.get("proxies") or []
        alive = sorted((d, x["name"]) for x in nodes if (d := last_delay(x)))
        rows.append([
            c("1", n),
            c("32" if alive else "31", f"{len(alive)}/{len(nodes)}") + c("2", " 可用"),
            *sub_info(p),
        ])
        top = []
        for d, nm in alive[:3]:
            if top:
                top.append(("  ·  ", "2"))
            top += [(short(nm) + " ", "2"), delay_seg(d)]
        tops.append(top or [("无可用节点", "31")])
    sub_box = []
    for row, top in zip(table(rows, maxw=maxw), tops):
        sub_box += [row, "  " + clip(top, maxw - 2)]

    inner = max(width(ln) for ln in line_box + sub_box)
    box("分流线", line_box, inner)
    if loc in AI_BLOCKED_LOC:
        warn(f"AI 线从 {loc} 出口，Claude / OpenAI 会拒绝 → `netsel tune AI`")
    if broken:
        warn(f"{'、'.join(broken)} 不通 → `netsel fix`（更新订阅并重新调出口）")
    if gw_down:
        warn(f"{'、'.join(gw_down)} 登录失败；ssh-direct 不经过 Clash，调出口修不了")
    box("订阅", sub_box, inner)


def sub_info(p):
    """订阅的 [流量, 到期, 更新时间] 三个单元格，快用完 / 快到期 / 久未更新时变色。"""
    info = p.get("subscriptionInfo") or {}
    total, used = info.get("Total", 0), info.get("Upload", 0) + info.get("Download", 0)
    if total:
        r = used / total
        quota = c("31" if r > 0.95 else "33" if r > 0.8 else None, f"{used / 2**30:.0f}/{total / 2**30:.0f} GB")
    else:
        quota = c("2", "流量未知")
    exp = info.get("Expire")
    if exp:
        days = (exp - time.time()) / 86400
        expire = c("31" if days < 3 else "33" if days < 7 else None,
                   "到期 " + time.strftime("%Y-%m-%d", time.localtime(exp)))
    else:
        expire = c("2", "不限期")
    try:
        age = (datetime.date.today() - datetime.date.fromisoformat((p.get("updatedAt") or "")[:10])).days
        updated = c("2" if age < 2 else "33", {0: "今天更新", 1: "昨天更新"}.get(age, f"{age} 天前更新"))
    except ValueError:
        updated = c("2", "未更新")
    return [quota, expire, updated]


def retest_groups(api, proxies):
    """测自动组而不是 select 组：mihomo 测完会按新结果重选，出口跟着刷新。
    顺序有讲究：先并行测各订阅的节点（互不重叠），再测 AI 的各档（前者的子集，错开以免挤占），
    最后测两个 fallback——它们的成员是上面的组，要等成员选好了，测出来的存活才是真的。
    AI 的测速给 5 秒：经中转握手到 Anthropic 常要 2 秒多，3 秒会把能用的节点误判成挂了。"""
    progress(True, "测速")
    tiers = (proxies.get("AI 自动") or {}).get("all") or []
    with cf.ThreadPoolExecutor() as ex:
        list(ex.map(api.group_delay, [f"{n} 自动" for n in subs(proxies)]))
    for g in tiers:
        api.group_delay(g, AI_TEST, AI_EXPECT, AI_TIMEOUT)
    api.group_delay("自动容灾")
    api.group_delay("AI 自动", AI_TEST, AI_EXPECT, AI_TIMEOUT)
    progress(False)


def ssh_config(host):
    """`ssh -G` 的结果 {键: 值}；~/.ssh/config 里没有这个别名时返回 None（ssh -G 会原样回显主机名）。"""
    try:
        out = subprocess.run(
            [SSH, "-G", host], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    cfg = dict(ln.split(" ", 1) for ln in out.splitlines() if " " in ln)
    if cfg.get("hostname", host).lower() == host.lower():
        return None
    return cfg


def ssh_login(host):
    """按 ~/.ssh/config 实际会走的路径登录一次，返回毫秒；失败返回 None。"""
    t = time.time()
    try:
        ok = subprocess.run(
            [SSH, "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host, "true"],
            capture_output=True,
            timeout=15,
        ).returncode == 0
    except subprocess.TimeoutExpired:
        ok = False
    return int((time.time() - t) * 1000) if ok else None


def probe_ssh(host):
    """(是否登录成功——未配置时为 None, 走哪条路, 登录毫秒)"""
    cfg = ssh_config(host)
    if cfg is None:
        return None, "", None
    via = "ssh-direct" if "ssh-direct" in cfg.get("proxycommand", "") else "经 Clash"
    ms = ssh_login(host)
    return bool(ms), via, ms


def fzf(lines, prompt):
    if not shutil.which("fzf"):
        die("需要 fzf")
    r = subprocess.run(
        ["fzf", "--ansi", "--prompt", prompt, "--height", "~60%", "--reverse",
         "--delimiter", "\t", "--with-nth", "2..", "--no-sort"],
        input="\n".join(lines), capture_output=True, text=True,
    )
    if r.returncode != 0:
        sys.exit(0)
    return r.stdout.strip().split("\t", 1)[0]


def cmd_pick(api, group=None):
    proxies = api.proxies()
    selectable = [n for n in LINES + subs(proxies) if proxies.get(n, {}).get("type") == "Selector"]
    if group is None:
        rows = [[c("1", g), hops(chain(proxies, g)[1:])] for g in selectable]
        lines = [f"{g}\t{row}" for g, row in zip(selectable, table(rows, flex=1, maxw=term_width() - 6))]
        group = fzf(lines, "分组 › ")
    if group not in proxies:
        die(f"没有分组 {group}；可选：{', '.join(selectable)}")

    progress(True)
    api.group_delay(group)
    progress(False)
    proxies = api.proxies()
    g = proxies[group]
    rows = []
    for name in g["all"]:
        p = proxies.get(name, {})
        is_group = p.get("type") in ("Selector", "URLTest", "Fallback")
        mark = c("32", "●") if name == g["now"] else c("2", "○")
        dl = "" if name == "DIRECT" else fmt_delay(last_delay(p))
        rows.append([mark, dl, short(name), hops(chain(proxies, name)[1:]) if is_group else ""])
    lines = [f"{name}\t{row}" for name, row in zip(g["all"], table(rows, right={1}, flex=3, maxw=term_width() - 6))]
    choice = fzf(lines, f"{group} › ")
    api.select(group, choice)
    print(f" {OK} {c('1', group)} → {choice}")


# ---------------------------------------------------------------- tune / update / fix
#
# 打分统一是（失败次数, 成功耗时的中位数），越小越好。


def score(times, rounds):
    ok = sorted(t for t in times if t)
    return rounds - len(ok), ok[len(ok) // 2] if ok else float("inf")


def fmt_score(s, rounds, slow):
    fails, med = s
    if fails >= rounds:
        return c("31", "全部失败")
    return fmt_delay(med, slow, slow * 2) + (c("31", f" 失败 {fails}") if fails else "")


def clearly_better(a, b, min_gain):
    """a 比 b 明显好：失败更少，或同样失败次数下快 20% 以上且至少快 min_gain 毫秒。
    差不多时不换，免得掐断走在当前出口上的长连接。"""
    if a[0] != b[0]:
        return a[0] < b[0]
    return b[1] - a[1] >= max(min_gain, 0.2 * b[1])


def tune_box(api, line, what, cands, orig, cells):
    """一条分流线的实测结果：每个候选一行（● 是当前出口），cells[cand] 是它的成绩单元格。"""
    proxies = api.proxies()
    rows = [
        [f"{c('32', '●') if cand == orig else c('2', '○')} {cand}", cells[cand], hops(chain(proxies, cand)[1:])]
        for cand in cands
    ]
    box(f"{line} · {what}", table(rows, flex=2, maxw=term_width() - 4))


def report(line, target, orig):
    """打印调整结果，返回出口是否变了。"""
    if target == orig:
        print(c("2", f"   ✓ 保持 {orig}"))
    else:
        print(f"   {c('33', '→')} {c('1', line)} 改为 {c('1', target)}" + c("2", f"（原来是 {orig}）"))
    return target != orig


def tune_http(api, line, rounds=3):
    """候选都是 mihomo 的组或 DIRECT，直接对候选测延迟，不用切换分组。
    默认候选（排第一的自动组 / DIRECT）稳定可用就用它：自动组自己会在节点间容灾，
    钉在某个订阅上反而没了容灾。它不可用时才钉到实测最好的候选。
    BY_SPEED 里的线默认候选「通」还不够：别的候选明显快过它就用别的，否则用它。"""
    url, expected = HTTP_LINES[line]
    g = api.proxies()[line]
    cands, orig = g["all"], g["now"]
    timeout = AI_TIMEOUT if line == "AI" else 5000

    def measure(cand):
        return score([api.delay(cand, url, expected, timeout) for _ in range(rounds)], rounds)

    progress(True, f"实测 {line}")
    with cf.ThreadPoolExecutor() as ex:
        scores = dict(zip(cands, ex.map(measure, cands)))
    progress(False)
    host = re.sub(r"^(www|api)\.", "", url.split("/")[2])
    tune_box(api, line, f"{host} ×{rounds}", cands, orig,
             {k: fmt_score(v, rounds, 500) for k, v in scores.items()})
    default = cands[0]
    allowed = [x for x in cands if x == orig or x in TUNE_ONLY.get(line, cands)]
    best = min(allowed, key=scores.get)
    if scores[best][0] >= rounds:
        hint = "；可以用 `netsel pick` 手动选" if line in TUNE_ONLY else ""
        print(c("31", f"   ✗ 能自动选的候选（{'、'.join(allowed)}）都不通，保持 {orig}{hint}"))
        return False
    pinned = line not in BY_SPEED and scores[default][0] != 0
    if line in BY_SPEED:  # 和默认的差不多就回到默认：直连不耗代理流量
        target = best if clearly_better(scores[best], scores[default], 50) else default
    elif not pinned:
        target = default
    else:  # 差不多时不动，免得掐断走在当前出口上的长连接
        target = best if clearly_better(scores[best], scores[orig], 50) else orig
    api.select(line, target)
    changed = report(line, target, orig)
    if pinned and target != default:
        warn(f"默认出口 {default} 不可用，暂时钉在 {target}；恢复后再执行一次 `netsel tune {line}`")
    return changed


def cmd_tune(api, lines=None):
    proxies = api.proxies()
    lines = lines or LINES
    for line in lines:
        if line not in LINES:
            die(f"没有分流线 {line}；可选：{', '.join(LINES)}")
        if line not in proxies:
            die(f"没有分组 {line}，先执行 `netsel setup`")
    retest_groups(api, proxies)  # 先让各自动组按最新测速重选，再比较候选
    changed = False
    for line in [x for x in HTTP_LINES if x in lines]:  # 按 HTTP_LINES 的顺序，见那里的注释
        changed |= tune_http(api, line)
    if changed:
        print(c("2", " 已建立的连接（如 Rex 隧道）仍走旧出口，断开重连后才换。"))


def update_provider(api, name):
    """更新一份订阅；成功返回 None，失败返回 mihomo 给的原因。"""
    try:
        api.call("PUT", f"/providers/proxies/{provider_key(name)}", timeout=60)
        return None
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read()).get("message") or f"HTTP {e.code}"
        except ValueError:
            return f"HTTP {e.code}"


def cmd_update(api):
    """mihomo 拉订阅走「订阅更新」组（默认直连）。直连失败的订阅，依次把这个组切到各订阅的
    自动组再重试——借别家机场的节点去拉，自家的节点放在最后（它可能正是坏掉的那份）。
    结束时切回原来的路线，日常的定时更新仍然直连。"""
    proxies = api.proxies()
    names = subs(proxies)
    w = max(width(n) for n in names)
    route = proxies.get(ROUTE)
    if route is None:  # 旧脚本没有这个组：只能按 mihomo 默认的路线拉一次
        warn(f"当前配置没有「{ROUTE}」组，失败时无法换路线重试；执行 `netsel setup` 更新分流脚本。")
    routes = route["all"] if route else [None]
    orig = route["now"] if route else None
    pending, errors = list(names), {}
    try:
        for r in routes:
            if not pending:
                break
            if r is not None:
                if r != "DIRECT" and not any(api.group_delay(r).values()):
                    continue  # 这条路线本身没有可用节点
                api.select(ROUTE, r)
            via = {"DIRECT": "直连", None: "按规则"}.get(r, f"经 {r}")
            progress(True, f"{via}拉取订阅")
            with cf.ThreadPoolExecutor() as ex:
                res = dict(zip(pending, ex.map(lambda n: update_provider(api, n), pending)))
            progress(False)
            for n in list(pending):
                if res[n] is None:
                    print(f" {OK} {pad(c('1', n), w)}  {c('2', via)}")
                    pending.remove(n)
                else:
                    errors[n] = f"{via}：{res[n]}"
                    if r is not None and r != routes[-1]:
                        print(c("2", f" · {pad(n, w)}  {via}失败（{res[n]}），换路线重试"))
    finally:
        if route is not None:
            api.select(ROUTE, orig)
    for n in pending:
        print(f" {BAD} {pad(c('1', n), w)}  {c('31', errors[n])}")
    return not pending


def cmd_fix(api):
    print(c("1", "更新订阅"))
    cmd_update(api)
    print()
    print(c("1", "调整出口"))
    cmd_tune(api)
    print()
    cmd_status(api, retest=False)


# ---------------------------------------------------------------- setup
#
# Verge 的配置文件归 Verge 所有：GUI 每改一次设置就整份重写，所以不能做成只读 symlink。
# 这里只把少数几项「收敛」到期望值，其余设置照旧归 GUI。只在手动执行 `netsel setup` 时改动，
# 幂等：没有差异就什么都不做。switch 只跑 `--check`（plan_setup 不带副作用）。
#
# Verge 运行时把配置握在内存里，退出时还会写回磁盘，所以有差异时顺序必须是
# 先退出 Verge → 再写文件 → 再启动，否则改动会被它覆盖掉。

# 控制器 secret 不归 netsel 管，用 Verge 当时的值（Api 每次从 clash-verge.yaml 读）：
#   - Verge 2.5.10 自己把控制器的 CORS 限死在它的几个来源，网页碰不到 127.0.0.1:9097；
#   - 同用户的进程本来就能读 clash-verge.yaml，随机 secret 几乎不加防护；
#   - Verge 启动时会把写进去的 secret 改回 set-your-secret，跟它抢只会每次都报差异、
#     重启后用旧 secret 探测失败。
CONTROLLER = "127.0.0.1:9097"
MARKER = "netsel setup"  # 生成的 Script.js 里带这个字样，用来判断是不是用户自己的脚本


def verge_remotes():
    """Verge 里导入的远程订阅。Verge 随时可能在重写 profiles.yaml，读到半截时当作空。"""
    try:
        with open(os.path.join(VERGE, "profiles.yaml")) as f:
            items = (yaml.safe_load(f) or {}).get("items") or []
    except (OSError, yaml.YAMLError):
        return []
    return [it for it in items if it.get("type") == "remote"]


def render_script(subs):
    # Verge 的全局脚本会在每份订阅上运行，按 Verge 里的订阅名区分。只在汇总订阅上启用
    # netsel 分流；它还没导入时脚本对所有订阅都不改写，保证救急订阅始终能直接选节点。
    # 按 URL 认订阅：Verge 给订阅起的名字（如 jms-1265282.yaml）不可控。
    summary = next(s for s in subs if s["summary"])
    managed_name = next((it.get("name") for it in verge_remotes() if it.get("url") == summary["url"]), None)
    found = [{k: s[k] for k in ("name", "key", "url", "ai")} for s in subs]
    with open(TEMPLATE) as f:
        return (f.read()
                .replace("__SUBS__", json.dumps(found, ensure_ascii=False, indent=2))
                .replace("__NETSEL_PROFILE__", json.dumps(managed_name, ensure_ascii=False)))


def sync_profiles(subs):
    """清单里有、Verge 里没有的订阅，经 clash://install-config 让 Verge 自己导入——profiles.yaml
    归 Verge 所有（它会整份重写），这里不直接写。Verge 里多出来的订阅只提示、不删：可能是
    临时加的救急订阅。"""
    want = {s["url"] for s in subs}
    for it in verge_remotes():
        if it.get("url") not in want:
            print(c("33", f"Verge 里有清单之外的订阅「{it.get('name')}」，未改动；不需要的话在 GUI 里删掉。"))
    have = {it.get("url") for it in verge_remotes()}
    missing = [s for s in subs if s["url"] not in have]
    for s in missing:
        # 只能带 url 一个参数：Verge（2.5.10）把 url= 之后的全部内容当链接，再带 &name=… 会
        # 被拼进订阅链接里。订阅名由 Verge 自己取（机场下发的名字），反正这里按 URL 认订阅。
        q = urllib.parse.urlencode({"url": s["url"]})
        print(f"导入订阅 {s['name']} …", end=" ", flush=True)
        # deep link 在 Verge 未运行时会把它拉起来；PATH 的讲究同 cmd_setup 末尾的 open
        env = dict(os.environ, PATH="/usr/bin:/bin:/usr/sbin:/sbin")
        subprocess.run(["/usr/bin/open", "-g", f"clash://install-config?{q}"], env=env)
        url = s["url"]
        if wait(lambda: url in {it.get("url") for it in verge_remotes()}, 60):
            print(c("32", "ok"))
        else:
            print(c("31", "60 秒内没出现在 Verge 里，下次 `netsel setup` 再试"))


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def converge_yaml(path, fn):
    """fn 原地改 dict；返回新文本，没有变化时返回 None。"""
    old = read(path) or ""
    d = yaml.safe_load(old) or {}
    before = json.dumps(d, sort_keys=True, default=str)
    fn(d)
    if json.dumps(d, sort_keys=True, default=str) == before:
        return None
    return "# Generated by Clash Verge\n\n" + yaml.safe_dump(
        d, allow_unicode=True, sort_keys=False
    )


# macOS 自带工具写绝对路径：home-manager activation 的 PATH 里只有少数 nix 包。
def verge_running():
    return subprocess.run(["/usr/bin/pgrep", "-xq", "clash-verge"]).returncode == 0


def quit_verge():
    """优先走 AppleEvent 正常退出；在没有 GUI 会话、或调用方没有「自动化」授权（activation
    里常见）时退回 SIGTERM。后者不会把内存里的配置写回，对这里反而无害。"""
    try:
        r = subprocess.run(
            ["/usr/bin/osascript", "-e", 'quit app "Clash Verge"'], capture_output=True, timeout=10
        )
        if r.returncode == 0 and wait(lambda: not verge_running(), 10):
            return
    except subprocess.TimeoutExpired:
        pass
    subprocess.run(["/usr/bin/pkill", "-TERM", "-x", "clash-verge"])


def wait(cond, timeout):
    end = time.time() + timeout
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.5)
    return False


def plan_setup(subs):
    """算出要让 Verge 收敛到清单还差什么，不做任何改动：(缺的订阅, {path: (新内容, 说明)})。"""
    have = {it.get("url") for it in verge_remotes()}
    missing = [s for s in subs if s["url"] not in have]

    writes = {}
    script_path = os.path.join(VERGE, "profiles", "Script.js")
    js = render_script(subs)
    if read(script_path) != js:
        writes[script_path] = (js, "全局扩展脚本（分流：" + "、".join(s["name"] for s in subs) + "）")

    def clash(d):
        if not d.get("external-controller"):
            d["external-controller"] = CONTROLLER

    def verge(d):
        d["enable_external_controller"] = True
        # 保留 GUI 的自定义绕过项；Tailscale 由系统 VPN 直接承载，不进 HTTP 代理。
        bypass = [s.strip() for s in re.split(r"[;,]", d.get("system_proxy_bypass") or "") if s.strip()]
        for entry in ("100.64.0.0/10", "fd7a:115c:a1e0::/48", "*.ts.net"):
            if entry not in bypass:
                bypass.append(entry)
        d["system_proxy_bypass"] = ",".join(bypass)  # macOS 使用逗号分隔

    for name, fn, what in [
        ("clash-verge.yaml", clash, "外部控制器地址"),
        ("verge.yaml", verge, "外部控制器与 Tailscale 系统代理绕过"),
    ]:
        new = converge_yaml(os.path.join(VERGE, name), fn)
        if new is not None:
            writes[os.path.join(VERGE, name)] = (new, what)
    return missing, writes


def pending(subs):
    """待应用的变更，一项一句；为空表示 Verge 已与清单一致。"""
    missing, writes = plan_setup(subs)
    out = ["缺订阅 " + "、".join(s["name"] for s in missing)] if missing else []
    return out + [what for _, what in writes.values()]


def drift_hint():
    """netsel 总览顶部的一行提示：清单与 Verge 不一致时提醒执行 setup，一致时为 None。"""
    if not os.path.isdir(VERGE):
        return None
    if not os.path.exists(SUBSCRIPTIONS):
        return f"订阅清单 {SUBSCRIPTIONS} 还没解密（本机有 ~/.config/sops/age/keys.txt 吗？）"
    todo = pending(load_subs())
    return "待应用：" + "；".join(todo) + "。执行 `netsel setup`" if todo else None


def cmd_check():
    """switch 时由 activation 调用：只报告，不导入、不写文件、不重启 Verge。"""
    if not os.path.isdir(VERGE):
        print("netsel：还没有 Clash Verge 配置目录（尚未首次启动），跳过检查。")
        return
    todo = pending(load_subs(wait_s=15))
    if not todo:
        print("Clash Verge：已与订阅清单一致。")
        return
    print(c("33", "Clash Verge 有待应用的变更，执行 `netsel setup` 应用（会重启 Verge，网络断几秒）："))
    for t in todo:
        print(c("33", f"  - {t}"))


def cmd_setup():
    if not os.path.isdir(VERGE):
        print("netsel setup: 还没有 Clash Verge 配置目录（尚未首次启动），先打开一次 Clash Verge。")
        return

    subs = load_subs()
    # 先导入：生成脚本要用汇总订阅在 Verge 里的名字
    sync_profiles(subs)
    missing, writes = plan_setup(subs)
    script_path = os.path.join(VERGE, "profiles", "Script.js")

    if not writes:
        print("Clash Verge：分流脚本与控制器配置已是最新。")
        return

    was_running = verge_running()
    if was_running:
        print("退出 Clash Verge …（网络会中断几秒）")
        quit_verge()
        if not wait(lambda: not verge_running(), 15):
            die("Clash Verge 没能退出，未做任何修改。")

    for path, (text, what) in writes.items():
        if path == script_path:
            old = read(path)
            if old is not None and MARKER not in old:
                shutil.copy2(path, path + ".bak")  # 只备份用户自己写的脚本，不备份上一次生成的
        with open(path, "w") as f:
            f.write(text)
        if path == script_path or path.endswith("clash-verge.yaml"):
            os.chmod(path, 0o600)  # 订阅 token / 控制器 secret
        print(f"已更新：{what}")

    if was_running:
        # open 拉起的 App 继承调用方环境；PATH 里没有 /usr/sbin 时 Verge 的 set_dns.sh 会因找不到
        # scutil 而没接管系统 DNS——TUN 下只剩裸 IP 连接，按域名的分流全部落空。
        env = dict(os.environ, PATH="/usr/bin:/bin:/usr/sbin:/sbin")
        subprocess.run(["/usr/bin/open", "-g", "-a", "Clash Verge"], env=env)
        # 每次重新构造 Api：Verge 启动时可能改写 clash-verge.yaml（含 secret），要用它改完的值
        if wait(lambda: probe(Api()), 30):
            print("Clash Verge 已重启，新配置生效。")
        else:
            print(c("33", "Clash Verge 已启动，但 30 秒内没连上控制器；稍后用 `netsel -n` 检查。"))
    else:
        print("Clash Verge 未运行，下次启动时生效。")


def probe(api):
    try:
        req = urllib.request.Request(
            api.base + "/version", headers={"Authorization": f"Bearer {api.secret}"}
        )
        with api.opener.open(req, timeout=2) as r:
            return r.status == 200
    except (OSError, urllib.error.URLError):
        return False


def main():
    args = sys.argv[1:]
    if args[:1] in (["-h"], ["--help"], ["help"]):
        print(__doc__)
        return
    if args[:1] == ["setup"]:
        return cmd_check() if "--check" in args else cmd_setup()
    api = Api()
    if not args or args == ["-n"] or args[:1] == ["status"]:
        return cmd_status(api, retest="-n" not in args)
    if args[0] == "pick":
        return cmd_pick(api, args[1] if len(args) > 1 else None)
    if args[0] == "tune":
        return cmd_tune(api, args[1:])
    if args[0] == "update":
        return cmd_update(api) or sys.exit(1)
    if args[0] == "fix":
        return cmd_fix(api)
    die(f"未知命令 {args[0]}，见 netsel -h")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
