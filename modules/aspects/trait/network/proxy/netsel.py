"""netsel：在终端里查看 Clash 分流状态、测速、切换节点。

    netsel                 总览：各分流线的当前出口、订阅状态、连通性（会先测一轮延迟）
    netsel -n              总览，但不重新测速（用 mihomo 上次的结果）
    netsel pick [组]       用 fzf 选择某个分组的出口；不带组名先选组
    netsel update          重新拉取所有订阅
    netsel setup           把 Clash Verge 收敛到仓库的配置：分流脚本、外部控制器、随机 secret；
                           有差异且 Verge 在运行时会重启它（switch 时由 activation 自动执行）
    netsel setup --no-restart   只检查；Verge 在运行时不动它，只列出待应用的差异

分组结构由 clash-script.js 决定；这里只认组名，不重复定义策略。
"""

import concurrent.futures as cf
import json
import os
import re
import secrets
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
TEST_URL = "https://www.gstatic.com/generate_204"
LINES = ["DGX", "国内", "国外", "AI"]  # 分流线，顺序即展示顺序
# Verge 里订阅名 → (分组名, provider 文件名)；按此顺序决定「自动容灾」的优先级
KNOWN_SUBS = [
    (re.compile(r"viking", re.I), "Vikings", "vikings"),
    (re.compile(r"jms|jmssub", re.I), "JMS", "jms"),
]

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
    """沿 now 一路展开到具体节点：国外 → 自动容灾 → Vikings 自动 → 🇯🇵 JP-…"""
    out = [name]
    while True:
        p = proxies.get(out[-1]) or {}
        nxt = p.get("now")
        if not nxt or nxt in out:
            return out
        out.append(nxt)


def subs(proxies):
    """当前配置里的订阅分组（Vikings / JMS …），由 setup 生成的结构推出来。"""
    fallback = proxies.get("自动容灾") or {}
    return [n.removesuffix(" 自动") for n in fallback.get("all", [])]


def provider_key(group):
    """订阅分组名 → provider 名（mihomo 里两者不能重名，见 clash-script.js）。"""
    return next((k for _, n, k in KNOWN_SUBS if n == group), group.lower())


# ---------------------------------------------------------------- 命令


def cmd_status(api, retest=True):
    proxies = api.proxies()
    if "DGX" not in proxies:
        die("当前配置里没有 DGX 分组：还没执行 `netsel setup`，或 Verge 还没应用全局脚本。")
    names = subs(proxies)

    if retest:
        retest_groups(api, names)
        proxies = api.proxies()

    # 连通性：分流线逐条实测（经 mihomo 的出口），DGX 另测真实 ssh 登录
    targets = {
        "国内": "https://www.baidu.com",
        "国外": TEST_URL,
        "AI": "https://api.anthropic.com",
    }
    with cf.ThreadPoolExecutor() as ex:
        futs = {k: ex.submit(api.delay, k, u) for k, u in targets.items()}
        ssh_fut = ex.submit(probe_ssh)
        reach = {k: f.result() for k, f in futs.items()}
        ssh_res = ssh_fut.result()

    print(c("1", f"  {pad('分流', 6)} {pad('出口', 50)}  连通性"))
    for line in LINES:
        ch = chain(proxies, line)
        leaf = proxies.get(ch[-1]) or {}
        path = " → ".join(short(x) for x in ch[1:])
        if leaf.get("type") not in ("Direct", "Reject") and ch[-1] not in ("DIRECT",):
            path += f" ({fmt_delay(last_delay(leaf))})"
        if line == "DGX":
            r = ssh_res
        else:
            r = f"{targets[line].split('//')[1]:<18} {fmt_delay(reach[line])}"
        print(f"  {pad(line, 6)} {pad(path, 50)}  {r}")

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
    顺序有讲究：先并行测各订阅的节点（互不重叠），再测 AI 优选（前者的子集，错开以免挤占），
    最后测两个 fallback——它们的成员是上面的组，要等成员选好了，测出来的存活才是真的。"""
    progress(True)
    with cf.ThreadPoolExecutor() as ex:
        list(ex.map(api.group_delay, [f"{n} 自动" for n in names]))
    api.group_delay("AI 优选")
    api.group_delay("自动容灾")
    api.group_delay("AI 自动")
    progress(False)


def pad(s, width):
    """按终端显示宽度补空格（CJK / emoji 占两格，ANSI 转义不占格）。"""
    plain = re.sub(r"\033\[[0-9;]*m", "", s)
    w = sum(2 if ord(ch) > 0x2E80 else 1 for ch in plain)
    return s + " " * max(0, width - w)


def probe_ssh():
    """按 ~/.ssh/config 实际会走的路径登录一次 DGX 网关，计时。"""
    host = "dgx-gw-0021"
    try:
        cfg = subprocess.run(
            ["ssh", "-G", host], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return "ssh 不可用"
    via = "ssh-direct" if "ssh-direct" in cfg else "经 Clash"
    t = time.time()
    try:
        ok = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host, "true"],
            capture_output=True,
            timeout=15,
        ).returncode == 0
    except subprocess.TimeoutExpired:
        ok = False
    ms = int((time.time() - t) * 1000)
    return f"ssh {host} [{via}] " + (c("32" if ms < 3000 else "33", f"{ms}ms 登录") if ok else c("31", "失败"))


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
# 这里只把少数几项「收敛」到期望值，其余设置照旧归 GUI。home-manager activation 每次 switch
# 都跑一遍，幂等：没有差异就什么都不做。
#
# Verge 运行时把配置握在内存里，退出时还会写回磁盘，所以有差异时顺序必须是
# 先退出 Verge → 再写文件 → 再启动，否则改动会被它覆盖掉。

CONTROLLER = "127.0.0.1:9097"
DEFAULT_SECRETS = ("", "set-your-secret")
MARKER = "netsel setup"  # 生成的 Script.js 里带这个字样，用来判断是不是用户自己的脚本


def render_script():
    with open(os.path.join(VERGE, "profiles.yaml")) as f:
        items = (yaml.safe_load(f) or {}).get("items") or []
    found = []
    for pat, name, key in KNOWN_SUBS:
        for it in items:
            if it.get("type") == "remote" and (
                pat.search(str(it.get("name") or "")) or pat.search(it.get("url") or "")
            ):
                found.append({"name": name, "key": key, "url": it["url"]})
                break
    if not found:
        die("在 Clash Verge 里没找到 Vikings / JMS 订阅。")
    with open(TEMPLATE) as f:
        js = f.read().replace("__SUBS__", json.dumps(found, ensure_ascii=False, indent=2))
    return js, [s["name"] for s in found]


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


def cmd_setup(restart=True):
    if not os.path.isdir(VERGE):
        print("netsel setup: 还没有 Clash Verge 配置目录（尚未首次启动），跳过。")
        return

    script_path = os.path.join(VERGE, "profiles", "Script.js")
    js, names = render_script()
    writes = {}  # path → (新内容, 说明)
    if read(script_path) != js:
        writes[script_path] = (js, "全局扩展脚本（分流：" + "、".join(names) + "）")

    def clash(d):
        if not d.get("external-controller"):
            d["external-controller"] = CONTROLLER
        if d.get("secret") in DEFAULT_SECRETS or d.get("secret") is None:
            d["secret"] = secrets.token_urlsafe(24)

    def verge(d):
        d["enable_external_controller"] = True

    for name, fn, what in [
        ("clash-verge.yaml", clash, "外部控制器地址 / 随机 secret"),
        ("verge.yaml", verge, "开启外部控制器"),
    ]:
        new = converge_yaml(os.path.join(VERGE, name), fn)
        if new is not None:
            writes[os.path.join(VERGE, name)] = (new, what)

    if not writes:
        print("Clash Verge：分流脚本与控制器配置已是最新。")
        return

    was_running = verge_running()
    if was_running and not restart:
        print("Clash Verge 正在运行，需要重启才能写入（它退出时会把内存里的旧配置写回）：")
        for _, what in writes.values():
            print(f"  - {what}")
        print("执行 `netsel setup` 完成。")
        return
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
            os.chmod(path, 0o600)  # 订阅 token / secret
        print(f"已更新：{what}")

    if was_running:
        # open 拉起的 App 继承调用方环境；activation 的 PATH 里没有 /usr/sbin，Verge 的 set_dns.sh
        # 会因找不到 scutil 而没接管系统 DNS——TUN 下只剩裸 IP 连接，按域名的分流全部落空。
        env = dict(os.environ, PATH="/usr/bin:/bin:/usr/sbin:/sbin")
        subprocess.run(["/usr/bin/open", "-g", "-a", "Clash Verge"], env=env)
        api = Api()
        if wait(lambda: probe(api), 30):
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
        return cmd_setup(restart="--no-restart" not in args)
    api = Api()
    if not args or args == ["-n"] or args[:1] == ["status"]:
        return cmd_status(api, retest="-n" not in args)
    if args[0] == "pick":
        return cmd_pick(api, args[1] if len(args) > 1 else None)
    if args[0] == "update":
        return cmd_update(api)
    die(f"未知命令 {args[0]}，见 netsel -h")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
