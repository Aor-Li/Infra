# 已知问题清单

对当前配置系统的一次全面体检记录。**所有结论均在本机实际求值验证过**，非静态推测；验证方式记在各条的「实测」里。

- 审计日期：2026-07-27
- 审计基线：commit `05f25ff`
- den input rev：`99cc0c5a1cc846cb1be681344b10d2731d430e13`

按严重程度排列。处理顺序建议见[末尾](#建议的处理顺序)。

---

## 一、真实缺陷

当前被「所有 home 恰好一模一样」这一巧合掩盖，没有暴露成构建错误。

### 1. homeManager 层的 `host` / `home` 上下文绑定到了错误的实体

**最严重的问题。**

aspect 只被实例化一次，`host` / `home` 绑定到该 system 的**第一个**实体，之后被该 system 下所有 home 复用。

实测（四个 x86_64-linux home 得到完全相同的 derivation）：

```
aor@Enten     drv = mzb2yla…      aor@Tobimune  drv = mzb2yla…
aor@Kumeyuri  drv = mzb2yla…      aor@philo     drv = mzb2yla…
```

用探针 aspect 读上下文，四者一致：

```
home.name = aor    home.hostName = Enten
home.host.graphical = true    home.host.role = desktop
```

即 `aor@Tobimune` 看到的是 **Enten** 的 host 实体；连 inventory 里根本没有对应 host 的 `aor@philo` 也拿到了 Enten。

**后果**——凡是在 **homeManager class** 里读上下文做门控的，判断依据都是错的：

| 位置 | 读取的上下文 |
| --- | --- |
| `trait/05-desktop/session/compositor/niri.nix:11` | `host.graphical && host.distro != "darwin"` |
| `trait/05-desktop/shell/quickshell/dank/dank-material-shell.nix:49` | `host.graphical or false` |
| `trait/06-develope/vcs/git.nix:18-19` | `home.email` / `home.fullname` |
| `trait/07-application/imagemagick.nix:8` | `host.graphical or false`（本就是死配置，见问题 3） |
| `trait/07-application/obsidian.nix:8` | `host.graphical or false`（同上） |

实证：`aor@philo` 无任何 host，却 `programs.niri.enable = true`、`programs.dank-material-shell.enable = true`。

**nixos class 里的门控不受影响**（boot、sleep、ssh、wsl、fonts、sunshine）——那些 scope 里 `host` 确实在上下文中。

**为何现在没炸**：三台 x86_64 host 的 `graphical` 都是 `true`，六个 home 的 `fullname` / `email` 完全相同。一旦 Tobimune 改成无桌面（对 `role = "server"` 是很自然的改动），Kumeyuri / Tobimune 的 home 桌面配置会**静默**跟着 Enten 走。

**修法尚未确定。** 以下三种写法实测均**没有**路由成功（三个 home 都没收到配置）：

- den 文档给出的 `den.aspects.<user>.provides.<hostName>`
- host 同名 aspect 挂 homeManager class（`den.aspects.Tobimune.homeManager`）
- 给 home 实体设 inline `aspect`（`den.homes.<system>."<u>@<h>".aspect`）

需进一步查 den 内部实现或向上游确认后再动手。

### 2. `dank-material-shell.nix` 缺少 `niri.nix` 里那套 `key`，home 一旦出现差异即求值失败

把 `aor@philo` 的 `fullname` / `email` 改成与其他 home 不同的值后，`aor@philo` 直接构建失败（Enten / Kumeyuri 仍正常）：

```
error: The option `programs.dank-material-shell.systemd.enable' in
`homeManager@desktop/shell/quickshell/<anon>:0' is already declared in …
```

`trait/05-desktop/session/compositor/niri.nix:22-25` 的注释已经准确预言了这个失败模式（「只在某个 home 的配置与其他 home 产生差异时才暴露」），并用显式 `key` 绕开了；
`trait/05-desktop/shell/quickshell/dank/dank-material-shell.nix:49-53` 的三个 `imports` 没有补同样的 `key`。

**这一条可以立刻单独修掉**，照抄 `niri.nix` 的 `key` 写法即可。

---

## 二、结构遗留

### 3. `den.aspects.app` 与 `den.aspects.service` 从未被 include —— 07 / 08 两层是死配置

`trait/07-application/app.nix` 定义了 `app.includes`，但没有任何地方 include `app` 本身：

- `aspects/default/default.nix:9-17` 只有 nix / system / security / network
- `aspects/default/host.nix`、`aspects/default/user.nix` 只有 dev / desktop

实测确认全部落空：

```
programs.obsidian.enable      = false
services.sunshine.enable      = false   (Enten)
imagemagick ∈ home.packages   = false
```

`den.aspects.service` 同样悬空（且本身是空壳，见问题 8）。

### 4. `inventory.nix` 里 6 处 `name = "aor@Xxx"` 是死配置

den 的 home 实体有 `config.name = lib.mkForce userName`（den 源码 `nix/lib/entities/home.nix:65`），显式赋的 `name` 必然被覆盖。探针实测 `home.name = "aor"`。

此外 `fullname` / `email` 在 6 个 home 里逐字重复，应下沉到 `den.schema.home` 的默认值。

### 5. 仓库根路径 `~/Den-Infra` 在 5 处硬编码，其中 3 处还内嵌了完整模块路径

- `trait/01-nix/tool/nh.nix:8`
- `trait/06-develope/editor/neovim/lazyvim/lazyvim.nix:6`
- `trait/06-develope/env/devenv.nix:8`
- `trait/06-develope/tool/fastfetch/fastfetch.nix:6`
- `trait/05-desktop/shell/quickshell/dank/dank-material-shell.nix:17`

其中三个 `mkOutOfStoreSymlink` 的目标把 `modules/aspects/trait/06-develope/…` 整条路径写死，源码里也都留了「路径写死，移动本目录时必须同步改这里」的注释——移动目录会**静默失效**。

`modules/meta/lib/` 是个空目录，显然本来就是留给这类共享 helper 的（见问题 8）。

### 6. `devshell` input 引入但完全没用

`flakes/devshell.nix` 声明了 input 又 import 了 flakeModule，但全仓没有任何 `devshells` / `perSystem.devshell` 定义。实测 `devShells.aarch64-darwin = [ ]`。

而 `flakes/README.md:24` 声称它「用于开发环境」。

### 7. 文档与实际目录结构脱节（refactor 后未同步）

根 `README.md:15-20` 的目录树：

| 文档写的 | 实际 |
| --- | --- |
| `modules/profile.nix` | `modules/inventory.nix` |
| `modules/metas/` | `modules/meta/` |
| `aspects/feature/` | `aspects/trait/` |

`README.md:25` 的链接同样指向不存在的 `modules/profile.nix`。

`modules/flakes/README.md:5` 引用 `../metas`、`../profile.nix`；`:33` 引用 `../aspects/feature/system/core/wsl-nixos.nix`（实为 `../aspects/trait/02-system/platform/wsl.nix`）。

### 8. 空目录与空壳 aspect

全空目录（git 不跟踪空目录，属本地残留）：`agent/`、`modules/meta/lib/`。

> `docs/` 在本清单落盘前也是空的，现已被本文件占用。

空壳 aspect（`{}`）：`system.hardware`、`desktop.appearance`、`session.display-manager`、`service`。

其中 `hardware` 是空的，而 Enten / Kuregumo / Tobimune 三台仍带着 `FIXME` 占位 `fileSystems`——硬件配置没有归口。

### 9. 命名不一致

- `06-develope` 拼写问题（→ `06-develop`）
- 汇总文件名与目录名时对时不对：`shell/shell.nix`、`system/system.nix` 对得上；`editor/editors.nix`、`lang/langs.nix`、`06-develope/dev.nix`、`07-application/app.nix` 对不上
- 目录名与 aspect 名不一致：`06-develope` → `dev`，`07-application` → `app`
- `desktop.shell`（桌面外壳）与 `dev.shell`（命令行 shell）同名不同义，两个目录都叫 `shell/shell.nix`
- `trait/03-network/network.nix:3-4` 用 `{ ... }: { includes = …; }` 函数形式，其余汇总节点都是直接 attrset

### 10. 未使用的模块参数遍布，且没有工具在管

`{ den, ... }` 但 `den` 未使用：`05-desktop/appearance/appearance.nix`、`08-service/service.nix`、`02-system/boot/boot.nix`、`02-system/platform/wsl.nix`、`02-system/platform/mac.nix`（`lib` 也未用）、五个 `entity/hosts/*.nix`。

原因是 `den.aspects.X` 在这些文件里只是 option 路径，而非模块参数。

`trait/06-develope/lang/nix.nix` 的工具集只有 nil / nixfmt / statix，**没有 deadnix**，所以这类死参数无人发现。

### 11. Kuregumo 重复了 `boot.nix` 已经做的事

`trait/02-system/boot/boot.nix:8-9` 已对 `env != "wsl"` 设了 systemd-boot + `canTouchEfiVariables`，
`entity/hosts/Kuregumo.nix:6-7` 又设一遍，而 Enten / Tobimune 没写——三台同类主机三种写法。

### 12. inventory 里语义可疑的组合

- **Kumeyuri**：`env = "wsl"` 却 `graphical = true` → 在 WSL 上开 niri / fcitx5 / DMS
- **Tobimune**：`role = "server"` 却 `graphical = true` → 服务器上开整套桌面栈

可能是有意的，但这两个 flag 恰好就是问题 1 会放大的那两个。

### 13. 零散小问题

- `trait/02-system/tools.nix:18` `environment.variables.EDITOR = "nvim"`，而 lazyvim 把 `nvim` alias 成 `nvim-lazy`——EDITOR 实际指向没有配置的 plain nvim
- `trait/01-nix/settings.nix:31` darwin 的 `trusted-users` 里有 `@wheel`，darwin 上没这个组
- `trait/06-develope/ai/ai.nix:8-14` 用 `os` class 加 numtide substituter，但 claude-code 是 `home.packages` 装的；由于 `meta/schema/user.nix` 设了 `den.schema.user.classes = [ ]`，HM 只走 standalone 路径，**拿不到**这个 cache
- secrets 的 `hosts/` 与 `users/` 目录尚不存在，`.sops.yaml` 与 tailscale 都还是 TODO 状态（已有注释说明，属已知）

---

## 建议的处理顺序

1. **问题 2** —— 真缺陷，可立刻单独修（照抄 `niri.nix` 的 `key` 写法），风险最低收益最直接。
2. **问题 3 / 4 / 6** —— 纯删／纯补的死配置清理，无行为变更风险。
3. **问题 5** —— 建议连同 `modules/meta/lib/` 一起解决（一个 `flakeRoot` + 相对路径 helper）。
4. **问题 7 / 8 / 9 / 10 / 11** —— 文档与一致性清理，可批量做；顺手把 deadnix 加进工具集。
5. **问题 1** —— 需先弄清 den 里 home scope 的正确写法（三种候选写法均已证伪），**确认后再动**。
