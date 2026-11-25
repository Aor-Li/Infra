# 绿联 NAS

外部设备记录：不由 NixOS / nix-darwin 管理，不加入 `den.hosts`，不生成系统配置。

| 项目 | 记录 |
| --- | --- |
| 型号 / CPU 架构 | DXP4800 Pro / x86_64（Intel i3-1315U） |
| UGOS 版本 | 1.15.1.0127（2026-11-25 客户端实查） |
| 局域网地址 | 192.168.3.127（BR-LAN1，2026-11-25 实查） |
| Docker / SSH 可用性 | Docker 项目已部署；Tailscale 地址 TCP 22 拒绝连接，未验证其他 SSH 端口 |
| Tailscale 设备名 | `ugreen-nas`，已登录并在线 |
| Tailscale IPv4 / MagicDNS 全名 | `100.110.96.22` / `ugreen-nas.taila9b4a0.ts.net` |
| 管理网页协议 / 端口 | HTTP 9999：返回 307，跳转 `/desktop/?os=ugospro`；TCP 9443 可达，HTTPS 尚未验收 |
| SMB 共享名 | 不配置挂载（用户当前不需要） |
| 部署与重启验收 | GHCR 部署与登录完成；Kumeyuri 直连、DNS、网页入口与 SMB 端口已验证；用户确认可登录；重启恢复待验证 |

`compose.yaml` 是本次 UGOS Pro Docker 部署使用的配置。重新部署时保留原项目和状态卷，
避免创建重复设备身份。

## Docker 部署

1. NAS 开启 SSH 后，执行 `test -c /dev/net/tun && echo TUN_OK`，确认 TUN 可用。
2. UGOS 的 Docker → 项目 → 创建，项目名填写 `tailscale`，粘贴本目录的 Compose。
3. 启动后查看日志中的登录链接，在浏览器中使用与其他设备相同的 Tailscale 账号授权。
   如果日志没有链接，可通过 SSH 执行：

   ```sh
   sudo docker exec -it tailscale tailscale up --hostname=ugreen-nas --accept-dns=false
   ```

4. 登录后检查：

   ```sh
   sudo docker exec tailscale tailscale status
   sudo docker exec tailscale tailscale ip -4
   ```

5. 把实际 IP、MagicDNS 全名、网页端口和共享名补入上表。重启容器后再次验收；
   维护窗口内重启 NAS，确认 Docker 和此项目自动启动。

状态保存在项目的 `tailscale-state` Docker volume 内，更新镜像时保留 volume；
不要执行 `docker compose down -v`。卷中包含设备身份凭据，不提交到仓库。
镜像使用 Tailscale 官方 GHCR 的 `ghcr.io/tailscale/tailscale:stable`，
部署时记录实际版本与 digest 后可进一步固定版本。
此配置提供 NAS 本机访问；不宣告局域网子网或出口节点。

2026-11-25 用户部署时访问 `registry-1.docker.io/v2/` 超时，镜像尚未拉取成功；
改用官方 GHCR 后用户确认部署成功，现已登录并通过下述连通检查。

如果 GHCR 镜像拉取也失败，先解决 Docker daemon 的镜像下载网络，再重试；
给容器设置 HTTP 代理不会解决 daemon 的拉取问题。

## 参考

- [绿联官方 Tailscale 部署说明](https://support.ugnas.com/detail/article/en-US/622)
- [Tailscale Docker 参数](https://tailscale.com/docs/features/containers/docker/docker-params)

## 连通验收（2026-11-25）

从 Kumeyuri 实查：设备 Online，MagicDNS 解析到 `100.110.96.22`。
`tailscale ping` 首次经 DERP(sfo)，随后建立 direct，实测响应 34ms / 6ms；
这是检查当时的结果，不代表持续性能。
HTTP 9999 返回 307 到 `/desktop/?os=ugospro`，TCP 445 可达。
用户已确认可登录 NAS；SMB 挂载不在当前需求范围内，未执行容器 / NAS 重启验收。

- 网页入口：`http://ugreen-nas.taila9b4a0.ts.net:9999/`
- Finder 连接服务器：`smb://ugreen-nas.taila9b4a0.ts.net`（使用 NAS 原账号）

## FreshRSS

2026-11-25 从 Kumeyuri 通过 Tailscale 实查：

- 访问地址：`http://ugreen-nas.taila9b4a0.ts.net:18080/`
- 服务响应正常，页面显示 FreshRSS 1.31.0，处于首次安装的语言选择步骤。
- 尚未完成数据库、管理员账号、订阅和定时抓取验收。
- 实际 Docker Compose、数据卷映射和抓取计划尚未读取，不以历史建议配置代替实机记录。
- SMB 挂载不在当前需求范围内；用户选择直接使用 NAS 服务。
