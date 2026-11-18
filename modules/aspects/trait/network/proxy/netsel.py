"""netsel：在终端里查看 Clash 分流状态、测速、切换节点。

    netsel                 总览：各分流线的当前出口、订阅状态、连通性（会先测一轮延迟）
    netsel -n              总览，但不重新测速（用 mihomo 上次的结果）
    netsel pick [组]       用 fzf 选择某个分组的出口；不带组名先选组
    netsel tune            给 AliCloud 线挑出口：逐个候选实测 `ssh AliCloud` 登录耗时，选最快的
    netsel update          重新拉取所有订阅
    netsel setup           把 Clash Verge 收敛到仓库的配置：导入清单里缺的订阅、分流脚本、
                           外部控制器；有差异且 Verge 在运行时会重启它（断网几秒）
    netsel setup --check   只列出待应用的变更，不做任何改动（switch 时由 activation 执行）

switch 不会改动代理：网络只在你执行 `netsel setup` 时才会变。不一致时 switch 与 `netsel`
总览都会提示。

分组结构由 clash-script.js 决定；这里只认组名，不重复定义策略。
订阅有哪些、什么顺序由 sops 下发的订阅清单决定（见 load_subs），不看 Verge 里导入了什么。
"""

import concurrent.futures as cf
import json
import os
import re
import shutil
import subprocess
import sys
import time
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
LINES = ["TurboAI", "AliCloud", "国内", "国外", "AI"]  # 分流线，顺序即展示顺序
# 按 ssh 登录实测连通性的分流线 → 测哪个 ssh 别名（来自对应 home entity 的 provides.ssh，经 SOPS 解密）
SSH_LINES = {"TurboAI": "TurboAI-gw", "AliCloud": "AliCloud"}
SSH = "/usr/bin/ssh"  # activation 的 PATH 里没有 ssh

TTY = sys.stdout.isatty()


def c(code, s):
    return f"\033[{code}m{s}\033[0m" if TTY else s


def fmt_delay(d):
    if not d:
        return c("31", "超时")
    color = "32" if d < 200 else "33" if d < 500 else "31"
    return c(color, f"{d}ms")


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

    def group_delay(self, group, timeout_ms=3000):
        q = urllib.parse.urlencode({"url": TEST_URL, "timeout": timeout_ms})
        try:
            return self.call(
                "GET", f"/group/{urllib.parse.quote(group)}/delay?{q}", timeout=30
            )
        except urllib.error.HTTPError:
            return {}  # 整组全挂时 mihomo 返回 503

    def delay(self, name, url, timeout_ms=5000):
        q = urllib.parse.urlencode({"url": url, "timeout": timeout_ms})
        try:
            r = self.call("GET", f"/proxies/{urllib.parse.quote(name)}/delay?{q}")
            return r.get("delay")
        except urllib.error.HTTPError:
            return None

    def select(self, group, name):
        self.call("PUT", f"/proxies/{urllib.parse.quote(group)}", {"name": name})


def last_delay(p):
    h = p.get("history") or []
    return h[-1]["delay"] if h else None


def short(name):
    """JMS-1265282@c12s1.portablesubmarines.com:7396 → c12s1:7396"""
    return re.sub(r"^JMS-\d+@([^.]+)\.[^:]+", r"\1", name)


def progress(on):
    if TTY:
        print(c("2", "测速中…") + "\r" if on else "\r\033[K", end="", flush=True)


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

    内容是 YAML 列表 [{name, url, summary?}]，顺序即「自动容灾」的优先级；恰好一项
    summary: true，它是全局脚本改写的汇总订阅，其余订阅激活时保留原生节点供救急。
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
        })
    if sum(s["summary"] for s in out) != 1:
        die("订阅清单里要恰好一项 summary: true（汇总订阅）。")
    return out


# ---------------------------------------------------------------- 命令


def cmd_status(api, retest=True):
    hint = drift_hint()
    if hint:
        print(c("33", hint))
        print()
    proxies = api.proxies()
    if not all(line in proxies for line in LINES):
        if hint:  # 脚本还是旧的（分流线改过名），提示里已经让执行 setup
            die("当前分流结构与仓库不一致，执行 `netsel setup`。")
        summary = next((s["name"] for s in load_subs() if s["summary"]), "汇总订阅") if os.path.exists(SUBSCRIPTIONS) else "汇总订阅"
        die(f"当前激活的不是汇总订阅，没有 netsel 分流：在 Clash Verge 里选中 {summary}"
            "（deep link 导入新订阅后 Verge 可能自动切到了它），或执行 `netsel setup`。")
    names = subs(proxies)

    if retest:
        retest_groups(api, names)
        proxies = api.proxies()

    # 连通性：分流线逐条实测（经 mihomo 的出口），SSH_LINES 另测真实 ssh 登录
    targets = {
        "国内": "https://www.baidu.com",
        "国外": TEST_URL,
        "AI": "https://api.anthropic.com",
    }
    with cf.ThreadPoolExecutor() as ex:
        futs = {k: ex.submit(api.delay, k, u) for k, u in targets.items()}
        ssh_futs = {k: ex.submit(probe_ssh, h) for k, h in SSH_LINES.items()}
        reach = {k: f.result() for k, f in futs.items()}
        ssh_res = {k: f.result() for k, f in ssh_futs.items()}

    print(c("1", f"  {pad('分流', 9)} {pad('出口', 50)}  连通性"))
    for line in LINES:
        ch = chain(proxies, line)
        leaf = proxies.get(ch[-1]) or {}
        path = " → ".join(short(x) for x in ch[1:])
        if leaf.get("type") not in ("Direct", "Reject") and ch[-1] not in ("DIRECT",):
            path += f" ({fmt_delay(last_delay(leaf))})"
        if line in SSH_LINES:
            r = ssh_res[line]
        else:
            r = f"{targets[line].split('//')[1]:<18} {fmt_delay(reach[line])}"
        print(f"  {pad(line, 9)} {pad(path, 50)}  {r}")

    print()
    print(c("1", "订阅"))
    provs = api.providers()
    for n in names:
        p = provs.get(provider_key(n)) or {}
        nodes = p.get("proxies") or []
        delays = [(last_delay(x), x["name"]) for x in nodes]
        alive = sorted((d, nm) for d, nm in delays if d)
        info = p.get("subscriptionInfo") or {}
        used = (info.get("Upload", 0) + info.get("Download", 0)) / 2**30
        total = info.get("Total", 0) / 2**30
        exp = info.get("Expire")
        quota = f"流量 {used:.0f}/{total:.0f} GB" if total else "流量 未知"
        if exp:
            quota += f"  到期 {time.strftime('%Y-%m-%d', time.localtime(exp))}"
        upd = (p.get("updatedAt") or "")[:10]
        print(
            f"  {pad(n, 8)} 可用 {len(alive):>2}/{len(nodes):<3} {quota}  更新于 {upd or '?'}"
        )
        for d, nm in alive[:3]:
            print(f"           {pad(fmt_delay(d), 7)} {short(nm)}")
        if not alive:
            print(c("31", "           无可用节点"))


def retest_groups(api, names):
    """测自动组而不是 select 组：mihomo 测完会按新结果重选，出口跟着刷新。
    顺序有讲究：先并行测各订阅的节点（互不重叠），再测 AI 的三档（前者的子集，错开以免挤占），
    最后测两个 fallback——它们的成员是上面的组，要等成员选好了，测出来的存活才是真的。"""
    progress(True)
    with cf.ThreadPoolExecutor() as ex:
        list(ex.map(api.group_delay, [f"{n} 自动" for n in names]))
    for g in ("AI 美国", "AI 非亚洲", "AI 兜底"):
        api.group_delay(g)
    api.group_delay("自动容灾")
    api.group_delay("AI 自动")
    progress(False)


def pad(s, width):
    """按终端显示宽度补空格（CJK / emoji 占两格，ANSI 转义不占格）。"""
    plain = re.sub(r"\033\[[0-9;]*m", "", s)
    w = sum(2 if ord(ch) > 0x2E80 else 1 for ch in plain)
    return s + " " * max(0, width - w)


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
    cfg = ssh_config(host)
    if cfg is None:
        return c("2", f"ssh {host} 未配置")
    via = "ssh-direct" if "ssh-direct" in cfg.get("proxycommand", "") else "经 Clash"
    ms = ssh_login(host)
    return f"ssh {host} [{via}] " + (c("32" if ms < 3000 else "33", f"{ms}ms 登录") if ms else c("31", "失败"))


def alicloud_hosts():
    """AliCloud 线按地址匹配；地址在 sops 解密出的 ssh 条目里，不进仓库。没配置时为空（不加规则）。"""
    cfg = ssh_config(SSH_LINES["AliCloud"])
    return [cfg["hostname"]] if cfg else []


def fzf(lines, prompt):
    if not shutil.which("fzf"):
        die("需要 fzf")
    r = subprocess.run(
        ["fzf", "--prompt", prompt, "--height", "~60%", "--reverse",
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
        lines = []
        for g in selectable:
            ch = chain(proxies, g)
            lines.append(f"{g}\t{pad(g, 8)} → {' → '.join(short(x) for x in ch[1:])}")
        group = fzf(lines, "分组> ")
    if group not in proxies:
        die(f"没有分组 {group}；可选：{', '.join(selectable)}")

    progress(True)
    api.group_delay(group)
    progress(False)
    proxies = api.proxies()
    g = proxies[group]
    lines = []
    for name in g["all"]:
        p = proxies.get(name, {})
        d = last_delay(p)
        is_group = p.get("type") in ("Selector", "URLTest", "Fallback")
        sub = f"→ {' → '.join(short(x) for x in chain(proxies, name)[1:])}" if is_group and p.get("now") else ""
        mark = "●" if name == g["now"] else " "
        dl = "" if name == "DIRECT" else fmt_delay(d)
        lines.append(f"{name}\t{mark} {pad(dl, 6)}  {short(name)}  {c('2', sub)}")
    choice = fzf(lines, f"{group}> ")
    api.select(group, choice)
    print(f"{group} → {choice}")


def cmd_tune(api, group="AliCloud", rounds=3):
    """mihomo 的测速只发 HTTP，测不了 ssh，所以这里自己测：把分组依次切到每个候选，各登录
    rounds 次，按（失败次数，中位数）排序选最好的。新出口只对新连接生效。"""
    host = SSH_LINES.get(group)
    if not host:
        die(f"只有 {', '.join(SSH_LINES)} 能按 ssh 实测调出口")
    cfg = ssh_config(host)
    if cfg is None:
        die(f"~/.ssh/config 里没有 {host}：请检查本机是否 include 了对应 home entity 的 provides.ssh")
    if "ssh-direct" in cfg.get("proxycommand", ""):
        die(f"{host} 经 ssh-direct 直连，不经过 Clash，调 {group} 线没有意义")
    proxies = api.proxies()
    g = proxies.get(group) or die(f"没有分组 {group}，先执行 `netsel setup`")
    orig = g["now"]
    print(c("1", f"实测 ssh {host} 登录（每个出口 {rounds} 次）"))
    scores = {}
    try:
        for cand in g["all"]:
            api.select(group, cand)
            times = [ssh_login(host) for _ in range(rounds)]
            ok = sorted(t for t in times if t)
            fails = rounds - len(ok)
            med = ok[len(ok) // 2] if ok else None
            scores[cand] = (fails, med if med is not None else float("inf"))
            leaf = " → ".join(short(x) for x in chain(api.proxies(), cand)[1:])
            res = c("31", "全部失败") if not ok else (
                c("32" if med < 3000 else "33", f"{med}ms") + (c("31", f"  失败 {fails}") if fails else ""))
            print(f"  {pad(cand, 12)} {pad(res, 16)} {c('2', leaf)}")
    except BaseException:
        api.select(group, orig)  # 中途 Ctrl-C / 出错时别把分组留在某个试探中的候选上
        raise
    best = min(scores, key=scores.get)
    if scores[best][0] == rounds:
        api.select(group, orig)
        die(f"所有出口都登录失败，{group} 保持 {orig}")
    api.select(group, best)
    print(f"{group} → {best}" + ("（与原来相同）" if best == orig else f"（原来是 {orig}）"))
    if best != orig:
        print(c("2", "已建立的连接（如 Rex 隧道）仍走旧出口，断开重连后才换。"))


def cmd_update(api):
    names = subs(api.proxies())
    for n in names:
        print(f"更新 {n} …", end=" ", flush=True)
        try:
            api.call("PUT", f"/providers/proxies/{provider_key(n)}", timeout=60)
            print(c("32", "ok"))
        except urllib.error.HTTPError as e:
            print(c("31", f"失败 {e.code}"))


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
    found = [{k: s[k] for k in ("name", "key", "url")} for s in subs]
    with open(TEMPLATE) as f:
        return (f.read()
                .replace("__SUBS__", json.dumps(found, ensure_ascii=False, indent=2))
                .replace("__ALICLOUD__", json.dumps(alicloud_hosts()))
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

    for name, fn, what in [
        ("clash-verge.yaml", clash, "外部控制器地址"),
        ("verge.yaml", verge, "开启外部控制器"),
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
        return cmd_tune(api, *args[1:2])
    if args[0] == "update":
        return cmd_update(api)
    die(f"未知命令 {args[0]}，见 netsel -h")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
