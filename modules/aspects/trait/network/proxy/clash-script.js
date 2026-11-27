// Clash Verge 全局扩展脚本模板（由 netsel setup 生成，勿手改）。`netsel setup` 把下面 SUBS 的占位符替换成
// sops 订阅清单里的 [{ name, key, url }]（见 clash.nix），写到 Verge 的 profiles/Script.js。全局脚本仅在
// 汇总订阅上改写配置；选择其他订阅时保持它们的原生节点和分组。
// 订阅链接含 token，仓库里只有密文，明文只出现在生成后的文件里。
// 占位符只能在代码里出现一次：替换是纯文本的，写进注释会把多行 JSON 漏到注释外面，脚本语法错误后
// Verge 会静默退回原始订阅。脚本跑在 Verge 内嵌的 JS 引擎里，不要依赖 URL 等宿主 API。
//
// 选择汇总订阅时，丢掉它自带的节点 / 分组 / 规则，改用 proxy-providers 同时拉取
// 所有订阅，再按下面几条线分流：
//   TurboAI   TurboAI 集群的域名，默认直连；`netsel tune` 实测 philoai.xyz，国外明显快过直连才走国外。
//             ssh 网关经 ssh-direct 绕开 Clash，不受这条线影响；不在加速节点后面的主机
//             （gitlab，见 TURBOAI_VIA_PROXY）单独走国外线
//   国内   GEOSITE cn / GEOIP CN，默认直连
//   国外   其余流量；默认「自动容灾」：按订阅顺序取第一个可用订阅里延迟最低的节点
//   AI    Claude / OpenAI 等不对香港开放的服务，四档逐级回落：美国 → 备用 → 非亚洲 → 其余允许地区；
//         HK/MO/CN/RU 永远不进（绝不退到不限地区的自动容灾，否则会从香港出去被 OpenAI 拦截）。
//         「备用」是清单里标了 ai: true 的订阅（JMS）：所有节点的 AI 出口都实测过在支持地区，
//         排在按节点名猜地区的两档前面；它不参与另外三档。
//         健康检查直接测 Anthropic API（见 AI_TEST），不测 gstatic
// 另有一个隐藏的「订阅更新」组：mihomo 拉订阅走它，默认直连；`netsel update` 直连失败时把它依次
// 切到各订阅的节点重试，完成后切回直连。
// 组名是 netsel 的 API，改名要同步改 netsel.py。

const SUBS = __SUBS__;
const NETSEL_PROFILE = __NETSEL_PROFILE__;

const TURBOAI_DOMAINS = ["philoai.xyz", "vegalb.com"];
// TurboAI 域名里不在国内加速节点后面的主机，改走国外线。ssh 网关与 philoai.xyz 解析到加速节点
// （ga-*.tencentcloudga003.cn），直连就快；gitlab 解析到 GCP 新加坡的裸 IP，直连跨境实测 15–30 KiB/s
// （git submodule update 拉十几分钟像卡死），经国外线 3MB/s。DOMAIN 规则排在 TURBOAI_DOMAINS 前面才能先命中
const TURBOAI_VIA_PROXY = ["gitlab.philoai.xyz"];
// AI 服务的静态下载 CDN（ChatGPT / Codex 安装包等，几百 MB）。GEOSITE category-ai-!cn 会把它们分到 AI 线，
// 而 AI 线按延迟选中的美国专线带宽极小（实测 0.2MB/s，brew 装 chatgpt 时下到一半断流）。
// 这些 CDN 不按地区拦截（经澳门节点实测 200、14MB/s），改走国外线
const AI_CDN_DOMAINS = ["oaistatic.com"];
const TEST_URL = "https://www.gstatic.com/generate_204";
// AI 线的健康检查：不带 key 访问 Anthropic API，连得上时返回 401。只测 gstatic 会把「能上网但到不了
// Anthropic」的节点当成可用而一直选着它（实际碰到过）。它分辨不了地区——香港节点同样返回 401，
// 地区仍然只靠下面的节点名过滤。
// 与 netsel.py 的 AI_TEST / AI_EXPECT 一致：mihomo 按 URL 字符串区分测速记录。
const AI_TEST = "https://api.anthropic.com/v1/models";
const AI_EXPECT = "401";
// 拉订阅走的组，见文件头
const ROUTE = "订阅更新";
// 订阅里用来展示流量 / 到期的假节点
const INFO_NODES = "剩余流量|距离下次重置|套餐到期|过期时间|官网";
// 地区只按代码 / 中文名匹配，不按旗帜：有的订阅 TW 节点挂的是 🇨🇳
const AI_US = "(?i)\\bUS\\b|美国";
// AI 服务不支持的地区
const AI_BLOCKED = "\\b(HK|MO|CN|RU)\\b|香港|澳门|中国|俄罗斯";
// 能用但尽量不用的亚洲地区（延迟低，但更容易被风控）
const ASIA = "\\b(JP|SG|TW|KR|MY|TH|VN|PH|ID|IN)\\b|日本|新加坡|台湾|韩国|马来|泰国|越南|菲律宾|印尼|印度";

function main(config, profileName) {
  if (!NETSEL_PROFILE || profileName !== NETSEL_PROFILE) return config;

  const providers = {};
  for (const s of SUBS) {
    // provider 与分组共用一个命名空间，所以 provider 用小写 key（forest），分组用显示名（Forest）
    providers[s.key] = {
      type: "http",
      url: s.url,
      path: `./proxy-providers/${s.key}.yaml`,
      interval: 86400,
      // 不指定时拉订阅走规则：订阅地址是 IP 时落到 MATCH,国外，国外一坏订阅也更新不了
      proxy: ROUTE,
      // 有的机场按 UA 决定下发格式与是否带 subscription-userinfo
      header: { "User-Agent": ["clash-verge/v2.5.8"] },
      "exclude-filter": INFO_NODES,
      "health-check": { enable: true, url: TEST_URL, interval: 600, lazy: true },
    };
  }
  const names = SUBS.map((s) => s.name);
  const auto = (n) => `${n} 自动`;
  // AI 按地区分档只看节点名；标了 ai 的订阅出口已实测，单独成「AI 备用」一档
  const regionKeys = SUBS.filter((s) => !s.ai).map((s) => s.key);
  const reserveKeys = SUBS.filter((s) => s.ai).map((s) => s.key);
  const urlTest = { url: TEST_URL, interval: 300, tolerance: 50, lazy: true };
  const aiTest = { ...urlTest, url: AI_TEST, "expected-status": AI_EXPECT };

  const tierGroups = [];
  if (regionKeys.length) {
    tierGroups.push({ name: "AI 美国", type: "url-test", use: regionKeys, filter: AI_US, ...aiTest });
  }
  if (reserveKeys.length) {
    tierGroups.push({
      name: "AI 备用",
      type: "url-test",
      use: reserveKeys,
      "exclude-filter": `(?i)${AI_BLOCKED}`,
      ...aiTest,
    });
  }
  if (regionKeys.length) {
    tierGroups.push(
      {
        name: "AI 非亚洲",
        type: "url-test",
        use: regionKeys,
        "exclude-filter": `(?i)${AI_BLOCKED}|${ASIA}`,
        ...aiTest,
      },
      { name: "AI 兜底", type: "url-test", use: regionKeys, "exclude-filter": `(?i)${AI_BLOCKED}`, ...aiTest },
    );
  }
  const aiTiers = tierGroups.map((g) => g.name);

  const groups = [
    { name: "TurboAI", type: "select", proxies: ["DIRECT", "国外"] },
    { name: "国内", type: "select", proxies: ["DIRECT", "国外"] },
    { name: "国外", type: "select", proxies: ["自动容灾", ...names] },
    // AI 备用单列出来，供 `netsel tune` 在 AI 自动不可用时钉住
    { name: "AI", type: "select", proxies: ["AI 自动", ...(reserveKeys.length ? ["AI 备用"] : []), "国外", ...names] },
    { name: "自动容灾", type: "fallback", proxies: names.map(auto), ...urlTest },
    // 按顺序回落，每档内部测速选优：
    //   AI 美国    名字带 US 的节点
    //   AI 备用    标了 ai: true 的订阅（JMS 节点名不带地区，但出口实测在 US/NL/JP）
    //   AI 非亚洲  排除不支持地区与亚洲：欧洲、澳洲等节点
    //   AI 兜底    只排除不支持地区，亚洲节点在这里才出现
    // 不能退到自动容灾——它可能首选 HK 节点，OpenAI 会直接 403。
    { name: "AI 自动", type: "fallback", proxies: aiTiers, ...aiTest },
    ...tierGroups,
    ...SUBS.flatMap(({ name: n, key }) => [
      { name: n, type: "select", proxies: [auto(n)], use: [key] },
      { name: auto(n), type: "url-test", use: [key], ...urlTest },
    ]),
    // 先直连，再按订阅顺序借各订阅的节点（netsel update 负责切换）
    { name: ROUTE, type: "select", proxies: ["DIRECT", ...names.map(auto)], hidden: true },
  ];

  // 地址是 IP 时 DOMAIN 规则匹配不到，要写成 IP-CIDR
  const hostRule = (h, target) =>
    /^[0-9.]+$/.test(h) ? `IP-CIDR,${h}/32,${target},no-resolve` : `DOMAIN,${h},${target}`;
  const subHosts = SUBS.map((s) => s.url.replace(/^[a-z]+:\/\//i, "").split(/[/?#:]/)[0]);
  const rules = [
    ...TURBOAI_VIA_PROXY.map((h) => `DOMAIN,${h},国外`),
    ...TURBOAI_DOMAINS.map((d) => `DOMAIN-SUFFIX,${d},TurboAI`),
    // 经 Clash 访问订阅地址时（如 Verge 自己更新订阅）走这条；mihomo 拉 provider 走 ROUTE 组，不看规则
    ...subHosts.map((h) => hostRule(h, "DIRECT")),
    "DOMAIN-SUFFIX,ts.net,DIRECT",
    "IP-CIDR6,fd7a:115c:a1e0::/48,DIRECT,no-resolve",
    "GEOSITE,private,DIRECT",
    "GEOIP,private,DIRECT,no-resolve",
    "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve", // tailscale
    ...AI_CDN_DOMAINS.map((d) => `DOMAIN-SUFFIX,${d},国外`),
    "GEOSITE,category-ai-!cn,AI",
    "GEOSITE,geolocation-!cn,国外",
    "GEOSITE,cn,国内",
    "GEOIP,CN,国内",
    "MATCH,国外",
  ];

  // DNS 写死，不依赖激活的订阅带不带（JMS 就不带）。国外域名按规则走代理、由远端解析，
  // 这里的上游只决定国内与直连域名的解析结果。
  // TurboAI 与订阅域名拿真实 IP：国内 DNS 才会解析到国内加速节点，ssh-direct 也不会碰上 fake-ip。
  const domestic = ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"];
  const dns = {
    ...(config.dns || {}),
    enable: true,
    "enhanced-mode": "fake-ip",
    "fake-ip-range": "198.18.0.1/16",
    "default-nameserver": ["223.5.5.5", "119.29.29.29"],
    nameserver: domestic,
    "proxy-server-nameserver": domestic,
    // MagicDNS 只能由本机 Tailscale DNS 回答，不能送去公共 DoH。
    "nameserver-policy": { ...((config.dns || {})["nameserver-policy"] || {}), "+.ts.net": "100.100.100.100" },
    "fake-ip-filter": [
      ...new Set([
        ...((config.dns || {})["fake-ip-filter"] || ["+.lan", "+.local"]),
        "+.ts.net",
        ...TURBOAI_DOMAINS.map((d) => `+.${d}`),
        ...subHosts,
      ]),
    ],
  };

  // 系统 DNS 不一定归 Clash：macOS 上 Tailscale 的「Use Tailscale DNS」会装一个全局 resolver，
  // 查询绕过 fake-ip 直接拿真实 IP（含 AAAA）。TUN 只看到裸 IP 时，按域名的分流全部落空，
  // IPv6 目的地址再被送进没有 IPv6 出口的节点，TLS 握手被掐断（nix-daemon 拉缓存就是这样挂的）。
  // 嗅探 SNI / Host 还原域名并覆盖目的地址，让分流与远端解析不依赖 DNS 走了哪条路。
  const sniffer = {
    ...(config.sniffer || {}),
    enable: true,
    "parse-pure-ip": true,
    "override-destination": true,
    sniff: {
      HTTP: { ports: [80, "8080-8880"] },
      TLS: { ports: [443, 8443] },
      QUIC: { ports: [443, 8443] },
    },
    "skip-domain": [
      ...new Set([...((config.sniffer || {})["skip-domain"] || []), "+.ts.net", "+.push.apple.com"]),
    ],
  };

  return {
    ...config,
    proxies: [],
    "proxy-providers": providers,
    "proxy-groups": groups,
    "rule-providers": {},
    rules,
    dns,
    sniffer,
    // Tailscale 自己的 VPN 路由承载 overlay，避免被 Clash TUN 再次捕获。
    tun: {
      ...(config.tun || {}),
      "route-exclude-address": [...new Set([
        ...((config.tun || {})["route-exclude-address"] || []),
        "100.64.0.0/10",
        "fd7a:115c:a1e0::/48",
      ])],
    },
    profile: { ...(config.profile || {}), "store-selected": true },
    "geodata-mode": true,
    "geox-url": {
      geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat",
      geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat",
      mmdb: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb",
    },
  };
}
