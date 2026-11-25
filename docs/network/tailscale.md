# Tailscale 入网与验收

## 范围与状态

目标：Enten、Kuregumo、Tobimune（NixOS），Magatsumi、Kumeyuri（Darwin）和绿联 NAS
加入同一个 tailnet，通过 Tailscale IP / MagicDNS 访问彼此提供的服务。
仓库配置已准备。Kumeyuri 与绿联 NAS 已完成安装和登录，两者已验证直连；其余主机部署、实际共享登录和重启验收尚未完成。

能力归属 `den.aspects.network.vpn.tailscale`，由五台 host 显式 include；
不进入 `den.default` / `network.includes`，standalone home 不自动安装。
NAS 的候选部署配置与设备信息见 [绿联 NAS](../../devices/ugreen-nas/README.md)。

## 已验证的设备

2026-11-25 19:55（Asia/Shanghai）通过本机 CLI 实查：

| 设备 | Tailscale IPv4 | MagicDNS 全名 | 状态 |
| --- | --- | --- | --- |
| Kumeyuri | 100.110.23.16 | kumeyuri.taila9b4a0.ts.net | Running / Online，客户端 1.104.7 |
| ugreen-nas | 100.110.96.22 | ugreen-nas.taila9b4a0.ts.net | Online；与 Kumeyuri 已建立 direct |

MagicDNS 已启用，健康告警为空；允许传入连接（ShieldsUp=false），未使用出口节点。
`netcheck` 显示 UDP、IPv4、IPv6 可用，无强制门户。
后续 NAS 验收：已验证直连、MagicDNS、HTTP 9999 入口及 TCP 445；尚未验证实际 SMB 登录与重启恢复。DERP 探测延迟不代表设备间延迟。

## 1. 准备 tailnet

登录 https://login.tailscale.com/admin/machines ，已有网络就沿用；
所有设备使用同一个 tailnet。到 DNS 页面检查 MagicDNS 是否开启。
已有 tailnet 还需检查 Access controls，确认策略允许目标设备间需要的端口。
不要直接覆盖已有访问策略。首次用浏览器登录，不需要把 auth key 写入 Nix 或 Compose。

## 2. 先接入当前 Mac

在对应 Mac 的 Infra 工作区运行（将名字换成本机）：

```sh
./scripts/bootstrap.sh Kumeyuri
open /Applications/Tailscale.app
```

激活会运行仓库已有的 Homebrew bundle 流程，也可能应用当前工作区其他改动；
先检查 `git diff`。完成 macOS 弹出的 VPN / 网络扩展授权，在 Tailscale 客户端登录。
菜单中确认已连接、允许传入连接；需要无人登录时也能访问的 Mac，检查客户端的
Run unattended 设置。Mac 睡眠时的可达性仍受电源与网络状态限制。

使用官方 app 内的 CLI 检查，避免与另装的 `tailscaled` 混用：

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4
```

Magatsumi 执行相同步骤，bootstrap 参数改为 `Magatsumi`。

### switch 后 Homebrew 显示已安装，但 app 不存在

2026-11-25 在 Kumeyuri 发现：首次安装在 sudo 密码提示处中断，Caskroom 已留下
`tailscale-app` 记录，但没有应用和 macOS 安装收据。随后 switch 的 Brewfile 已包含
该 cask，Homebrew 仍可能按已有记录跳过安装。

先检查 `brew info --cask tailscale-app` 与
`test -x /Applications/Tailscale.app/Contents/MacOS/Tailscale` 是否矛盾。
确认属于此状态后，在本机终端修复一次：

```sh
brew reinstall --cask tailscale-app
test -x /Applications/Tailscale.app/Contents/MacOS/Tailscale && echo Tailscale_OK
open /Applications/Tailscale.app
```

这是修复本机的中断安装状态；仓库中的声明继续由 nix-darwin / Homebrew bundle 管理。
安装需要本机管理员密码。修复后再验收 app 与登录状态，无需反复 switch。

## 3. 接入 NixOS

每台实机从本机 Infra 工作区运行，下例为 Tobimune：

```sh
./scripts/bootstrap.sh Tobimune
sudo tailscale up
tailscale status
tailscale ip -4
```

打开 `tailscale up` 输出的链接，在同一个 tailnet 内授权。
之后 systemd 自动启动服务，设备身份保存在本机，不需要每次 switch 登录。
Enten / Kuregumo 按各自名字执行；两者仓库根文件系统仍标记为占位配置，
必须先与实机硬件配置核对，不能直接照搬整机 switch。

NixOS 开放 Tailscale UDP 监听端口以帮助直连；没有全信任 tailscale0。
服务仍需监听 Tailscale IP 或所有接口，系统防火墙仍需允许需要的端口。
Tailscale 入网不会自动启用 SMB、网页服务或 SSH 服务。

## 4. NAS 与逐项验收

完成 NAS 设备记录中的步骤后，依次检查：

1. 管理后台所有预期设备在线，记录实际 Tailscale IPv4 和 DNS 名。
2. 两台设备间运行 `tailscale ping <对端 Tailscale IP>`；Mac 使用上面的 app CLI 路径。
   输出 `direct` 表示直连，`DERP` 表示经过中继；中继可用但性能可能受限。
3. 用浏览器访问 NAS 原有协议与端口，只把局域网 IP 换成 Tailscale IP。
4. macOS Finder → 前往 → 连接服务器，输入 `smb://<NAS Tailscale IP>/<共享名>`，
   使用 NAS 原有账号登录。共享名与权限以 NAS 实际设置为准。
5. IP 访问成功后改用 MagicDNS 名重试。其他客户端也逐一验收。
6. 从手机热点等外部网络重试，确认远程路径可用；重启后再次检查。

`tailscale ping` 成功只证明隧道可达，网页 / SMB 要分别验证。
若失败，依次检查服务监听地址与端口、NAS / 主机防火墙、tailnet 访问策略。
Clash 现有脚本包含 `100.64.0.0/10` 直连规则；使用 TUN / 自定义 DNS 时，
若 DNS 名访问失败先测试 Tailscale IP，再检查代理是否接管了 MagicDNS 查询。

常驻 NAS / 服务器可在后台机器菜单检查 key expiry，按运维需求决定是否关闭到期；
关闭到期意味着设备长期保留访问资格。先完成连通验收，再做这项选择。

## 官方资料

- [macOS 客户端的区别](https://tailscale.com/docs/concepts/macos-variants)
- [Homebrew 官方 tailscale-app cask](https://formulae.brew.sh/cask/tailscale-app)
- [绿联 NAS 记录与部署](../../devices/ugreen-nas/README.md)

## macOS 系统代理与 MagicDNS（2026-11-25 已修复）

症状：FreshRSS 绕过代理 HTTP 200，经 Clash HTTP 代理为 502，内置浏览器打不开。
原因：系统代理绕过列表缺少 Tailscale 地址和 `*.ts.net`。

修复归属 `network/proxy`：`netsel setup` 在保留现有自定义项的基础上追加
`100.64.0.0/10`、`fd7a:115c:a1e0::/48` 和 `*.ts.net`。macOS 使用逗号分隔，
不能使用 Windows 的分号格式。全局 Clash 脚本同时加入 Tailscale 直连、MagicDNS
专用 DNS 策略、fake-IP 排除与 TUN route-exclude-address。

本机已通过仓库 setup 的配置生成逻辑应用并重启 Clash。验证：CFNetwork 系统代理
解析返回 `kCFProxyTypeNone`；遵循系统设置的 URLSession 请求 HTTP 200，页面包含
FreshRSS；NAS 仍为 direct。内置浏览器自动检查工具超时，需在原标签页刷新确认。

后续 switch 会安装新版 netsel，其他 Mac 仍需各自 switch 后执行 `netsel setup`。
不要在 shell 中显式强制代理访问 Tailscale 地址，那会绕过系统的 bypass 判断。
