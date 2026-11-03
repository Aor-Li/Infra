// Clash Verge 全局扩展脚本模板（由 netsel setup 生成，勿手改）。`netsel setup` 把下面 SUBS 的占位符替换成从 Verge 订阅里读出的
// [{ name, key, url }]，写到 Verge 的 profiles/Script.js（全局脚本，对任何激活的订阅都生效）。
// 订阅链接含 token，只出现在生成后的文件里，不进仓库。
// 占位符只能在代码里出现一次：替换是纯文本的，写进注释会把多行 JSON 漏到注释外面，脚本语法错误后
// Verge 会静默退回原始订阅。脚本跑在 Verge 内嵌的 JS 引擎里，不要依赖 URL 等宿主 API。
//
// 不管激活的是哪份订阅，这里都丢掉它自带的节点 / 分组 / 规则，改用 proxy-providers 同时拉取
// 所有订阅，再按下面三条线分流：
//   DGX   philoai 集群（ssh 网关在阿里云加速器后面），默认直连
//   国内   GEOSITE cn / GEOIP CN，默认直连
//   国外   其余流量；默认「自动容灾」：按订阅顺序取第一个可用订阅里延迟最低的节点
//   AI    Claude / OpenAI 等不对香港开放的服务，默认在 JP/SG/US/TW 节点里测速选优，全挂时退到自动容灾
// 组名是 netsel 的 API，改名要同步改 netsel.py。

const SUBS = __SUBS__;

const DGX_DOMAINS = ["philoai.xyz", "vegalb.com"];
const TEST_URL = "https://www.gstatic.com/generate_204";
// 订阅里用来展示流量 / 到期的假节点
const INFO_NODES = "剩余流量|距离下次重置|套餐到期|过期时间|官网";
const AI_REGIONS = "(?i)\\b(JP|SG|US|TW)\\b|日本|新加坡|美国|台湾";

function main(config) {
  const providers = {};
  for (const s of SUBS) {
    // provider 与分组共用一个命名空间，所以 provider 用小写 key（vikings），分组用显示名（Vikings）
    providers[s.key] = {
      type: "http",
      url: s.url,
      path: `./proxy-providers/${s.key}.yaml`,
      interval: 86400,
      // 有的机场按 UA 决定下发格式与是否带 subscription-userinfo
      header: { "User-Agent": ["clash-verge/v2.5.8"] },
      "exclude-filter": INFO_NODES,
      "health-check": { enable: true, url: TEST_URL, interval: 600, lazy: true },
    };
  }
  const names = SUBS.map((s) => s.name);
  const auto = (n) => `${n} 自动`;
  const urlTest = { url: TEST_URL, interval: 300, tolerance: 50, lazy: true };

  const groups = [
    { name: "DGX", type: "select", proxies: ["DIRECT", "国外"] },
    { name: "国内", type: "select", proxies: ["DIRECT", "国外"] },
    { name: "国外", type: "select", proxies: ["自动容灾", ...names] },
    { name: "AI", type: "select", proxies: ["AI 自动", "国外", ...names] },
    { name: "自动容灾", type: "fallback", proxies: names.map(auto), ...urlTest },
    // AI 优选只认名字里带地区的节点（JMS 的节点名不带地区，所以这里实际只有 Vikings）；
    // 它全挂时 AI 自动退到自动容灾，不至于没有出口
    { name: "AI 自动", type: "fallback", proxies: ["AI 优选", "自动容灾"], ...urlTest },
    { name: "AI 优选", type: "url-test", use: SUBS.map((s) => s.key), filter: AI_REGIONS, ...urlTest },
    ...SUBS.flatMap(({ name: n, key }) => [
      { name: n, type: "select", proxies: [auto(n)], use: [key] },
      { name: auto(n), type: "url-test", use: [key], ...urlTest },
    ]),
  ];

  const subHosts = SUBS.map((s) => s.url.replace(/^[a-z]+:\/\//i, "").split(/[/?#:]/)[0]);
  const rules = [
    ...DGX_DOMAINS.map((d) => `DOMAIN-SUFFIX,${d},DGX`),
    ...subHosts.map((h) => `DOMAIN,${h},DIRECT`),
    "GEOSITE,private,DIRECT",
    "GEOIP,private,DIRECT,no-resolve",
    "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve", // tailscale
    "GEOSITE,category-ai-!cn,AI",
    "GEOSITE,geolocation-!cn,国外",
    "GEOSITE,cn,国内",
    "GEOIP,CN,国内",
    "MATCH,国外",
  ];

  // DNS 写死，不依赖激活的订阅带不带（JMS 就不带）。国外域名按规则走代理、由远端解析，
  // 这里的上游只决定国内与直连域名的解析结果。
  // DGX 与订阅域名拿真实 IP：国内 DNS 才会解析到国内加速节点，ssh-direct 也不会碰上 fake-ip。
  const domestic = ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"];
  const dns = {
    ...(config.dns || {}),
    enable: true,
    "enhanced-mode": "fake-ip",
    "fake-ip-range": "198.18.0.1/16",
    "default-nameserver": ["223.5.5.5", "119.29.29.29"],
    nameserver: domestic,
    "proxy-server-nameserver": domestic,
    "fake-ip-filter": [
      ...new Set([
        ...((config.dns || {})["fake-ip-filter"] || ["+.lan", "+.local"]),
        ...DGX_DOMAINS.map((d) => `+.${d}`),
        ...subHosts,
      ]),
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
    profile: { ...(config.profile || {}), "store-selected": true },
    "geodata-mode": true,
    "geox-url": {
      geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat",
      geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat",
      mmdb: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb",
    },
  };
}
