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

**后果**——凡是在 **homeManager class** 里读上下文做门控的，判断依据都是错的（下表为审计当时的状态；`graphical` 已于 2026-08-02 移除，见文末追加）：

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

---

#### 追加调查（2026-07-28）—— 状态：**暂缓处理**

对 den 源码（`nix/lib/entities/home.nix`、`nix/lib/aspects/fx/`）和官方文档（den.denful.dev）做了进一步核实，并在本仓库用探针 aspect 重新实测，结论如下：

- **这不是配置姿势问题，是 den 当前锁定版本（`99cc0c5a1cc846cb1be681344b10d2731d430e13`）resolver 的真实缺陷**，上游已有人报告为 [den#635](https://github.com/vic/den/issues/635)（"multiple standalone user@host homes sharing a user aspect resolve host-keyed config against the first home only"），但报告者次日自行留言称"filed by an inadequately constrained AI agent, please disregard"，维护者未验证真伪即关闭为 not planned。本仓库的独立复现（见下）证实该 bug **确实存在**，且命中当前实际生效的路径——`scripts/bootstrap.sh` 明确让 home-manager 始终走 standalone（不作为 nixos/darwin 模块运行）。
- **精确根因**：不是"同一 system 下的 home 全部错误共享第一个 host"，而是**多个 home 共享同一个 den 用户名（`userName`，即 home 名字 `@` 前面那段）时发生身份碰撞**，resolver 只保留其中一个的 host 绑定。实测对照：`zzz1@Enten` / `zzz2@Tobimune`（用户名不同、各自独立 aspect）host 绑定完全正确；而只要用户名相同（如仓库里全部 6 个 home 都叫 `aor`），無论是共享同一个 aspect、还是给每个 home 单独覆盖 `.aspect` 选项，一律错误共享第一个 home 的 host 绑定。这一发现比原 issue 更精确，尚未反馈回上游。
- **已确认无效的路径**：`provides.<hostName>`、`policy.when` 门控、参数化 include 门控、per-home `.aspect` 覆盖——只要用户名共享，全部失败。
- **已确认不受影响的路径**：declared-host 模式（`den.hosts.<system>.<Host>.users.aor` + host 层 `provides`），因为每台机器是完全独立的顶层 `nixosConfigurations` 求值，不存在跨 home 的身份碰撞。但切换到这条路径意味着 home-manager 不再能独立于 `nixos-rebuild`/`darwin-rebuild` 单独构建，与 `bootstrap.sh` 当前"standalone 优先、可单独 switch home"的设计取向冲突。

**决定（2026-07-28）：暂缓处理。** 不采用"给每个 home 起不同 den 用户名再手工覆盖 `home.username`"这类绕过身份系统的写法（不是 den 的设计意图，只是绕开 bug 的手工拼接）；也暂不切换到 declared-host 模式（改动面大、放弃 standalone 独立构建的好处）。现状维持"六个 home 配置恰好相同"，**不得改变**（改动任何一台机器的 host 差异化设置或 home 的 `homeManager` 层门控内容，都会因为这个 bug 静默配错或直接构建失败——继续保持现状是安全的，动了就会暴露问题）。后续如需处理，优先级见下：

1. 把上面这条更精确的复现补充/重新提交到 den#635，请求重新打开。
2. 若上游长期不修，再评估是否值得为桌面差异化切到 declared-host 模式。

#### 追加记录（2026-08-02）—— 上面那条「不得改变」的约束**已经破了**

`host.graphical` 这个 flag 连同它在 5 个 aspect 里的门控被整体移除，门控职责下放给 `includes`（哪台机器 include `desktop` / `app`）。这个改动本身对 nixos class 是干净的——Enten / Kuregumo 拿到 niri + sunshine + fcitx5，Tobimune（没 include `desktop` / `app`）一个都没拿到。

但它把问题 1 从潜伏状态推了出来：`graphical or false` 恒假时六个 home 恰好一模一样，这个巧合正是上面「维持现状是安全的」的全部依据；一旦门控消失，`den.aspects.app` 的 homeManager 层（obsidian / imagemagick）立刻显出错误路由。

实测，两台 aarch64-darwin host 都 `include` 了 `den.aspects.app`，但只有一个 home 收到：

```
aor@Magatsumi   programs.obsidian.enable = true    drv 变了
aor@Kumeyuri    programs.obsidian.enable = false   drv 与移除前逐字节相同
```

`aor@Magatsumi` 是本仓库第一个不再与同 system 其他 home 共享 derivation 的 home。**这不是新 bug，是问题 1 的直接显形**，无法在不重新引入门控的前提下消除。

**决定：接受并记录，不回退。** 后续给 home 侧做任何差异化之前，都必须先解决问题 1；在那之前，凡是挂在 `homeManager` class 上的 aspect 都要默认「落到哪个 home 是不确定的」。

顺带：`den.aspects.desktop` 的 homeManager 层（niri、dank-material-shell）当前**根本没到达任何 home**——六个 home 的 `programs.niri` / `programs.dank-material-shell` 全部不存在，移除门控前后都是如此。也就是说 home 侧桌面栈整体是死的，问题 2 的 `already declared` 目前无从触发。

### 2. `dank-material-shell.nix` 缺少 `niri.nix` 里那套 `key`，home 一旦出现差异即求值失败 —— 状态：**暂缓处理，与问题1同源**

把 `aor@philo` 的 `fullname` / `email` 改成与其他 home 不同的值后，`aor@philo` 直接构建失败（Enten / Kumeyuri 仍正常）：

```
error: The option `programs.dank-material-shell.systemd.enable' in
`homeManager@desktop/shell/quickshell/<anon>:0' is already declared in …
```

`trait/05-desktop/session/compositor/niri.nix:22-25` 的注释已经准确预言了这个失败模式（「只在某个 home 的配置与其他 home 产生差异时才暴露」），并用显式 `key` 绕开了；
`trait/05-desktop/shell/quickshell/dank/dank-material-shell.nix:49-53` 的三个 `imports` 没有补同样的 `key`。

**追加调查（2026-07-28）—— 与问题1同源，非独立 bug**：

`niri.nix` 的注释已经点破了机制——「aspect 带 `host` 上下文时会在多个 scope 上扇出，同一个上游模块会被 import 多次」。这个"扇出"正是问题1根因（6 个 home 共享同一 den 用户名 `aor`，resolver 把它们当同一身份，aspect 只实例化一次）的直接后果：本应各自独立的 home 复用了同一个匿名 `imports` 模块对象，module 系统靠 `key` 去重，缺了它、且几个 home 配置出现差异时就报 `already declared`。

`niri.nix` 手工补的 `key = "den:niri-home-module"` / `key = "den:niri-enable"` 只是**消除了崩溃症状**，并不修复扇出本身——补 key 之后 `aor@philo` 依然会静默拿到别人（如 Enten）的 `host` 绑定，只是不再因选项冲突报错，行为会退化成问题1描述的"静默配错"而非"构建失败"。

**决定：暂缓处理，与问题1一并处理。** 单独给 `dank-material-shell.nix` 补 `key` 只是照抄姑息写法，不解决根因，且会把"构建失败"这个尚可见的报错信号也消掉，掩盖问题1。在问题1的路由方式确认之前，不单独修这一条。

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

**更新（2026-08-02）—— `app` 这半条已解决。** `entity/hosts/` 下的 Enten / Kuregumo / Kumeyuri / Magatsumi 四个文件现在都显式 `include` 了 `den.aspects.app`，去掉 `graphical` 门控后实测 `services.sunshine.enable = true`（Enten / Kuregumo）、`programs.obsidian.enable = true`（`aor@Magatsumi`，路由错误见问题 1）。`den.aspects.service` 仍然悬空。

### 4. `inventory.nix` 里 6 处 `name = "aor@Xxx"` 是死配置

den 的 home 实体有 `config.name = lib.mkForce userName`（den 源码 `nix/lib/entities/home.nix:65`），显式赋的 `name` 必然被覆盖。探针实测 `home.name = "aor"`。

此外 `fullname` / `email` 在 6 个 home 里逐字重复，应下沉到 `den.schema.home` 的默认值。

### 5. 仓库根路径 `~/Infra` 在 5 处硬编码，其中 3 处还内嵌了完整模块路径

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

`trait/02-system/boot/boot.nix:8-9` 已对 `virt != "wsl"` 设了 systemd-boot + `canTouchEfiVariables`，
`entity/hosts/Kuregumo.nix:6-7` 又设一遍，而 Enten / Tobimune 没写——三台同类主机三种写法。

### 12. inventory 里语义可疑的组合

- **Kumeyuri**：`virt = "wsl"` 却 `graphical = true` → 在 WSL 上开 niri / fcitx5 / DMS
- **Tobimune**：`role = "server"` 却 `graphical = true` → 服务器上开整套桌面栈

可能是有意的，但这两个 flag 恰好就是问题 1 会放大的那两个。

**更新（2026-08-02）—— 已解决。** `graphical` 已从 host schema 和全部 aspect 中移除，桌面栈改由 `includes` 决定：Kumeyuri 只 include `app`，Tobimune 两个都不 include，实测两台都不再拿到 niri / fcitx5 / DMS。

### 13. 零散小问题

- `trait/02-system/tools.nix:18` `environment.variables.EDITOR = "nvim"`，而 lazyvim 把 `nvim` alias 成 `nvim-lazy`——EDITOR 实际指向没有配置的 plain nvim
- `trait/01-nix/conf.nix`（审计时名为 `settings.nix`）darwin 的 `trusted-users` 里有 `@wheel`，darwin 上没这个组
- `trait/06-develope/ai/ai.nix:8-14` 用 `os` class 加 numtide substituter，但 claude-code 是 `home.packages` 装的；由于 `meta/schema/user.nix` 设了 `den.schema.user.classes = [ ]`，HM 只走 standalone 路径，**拿不到**这个 cache
- secrets 的 `hosts/` 与 `users/` 目录尚不存在，`.sops.yaml` 与 tailscale 都还是 TODO 状态（已有注释说明，属已知）

---

## 建议的处理顺序

1. **问题 3 / 4 / 6** —— 纯删／纯补的死配置清理，无行为变更风险。
2. **问题 5** —— 建议连同 `modules/meta/lib/` 一起解决（一个 `flakeRoot` + 相对路径 helper）。
3. **问题 7 / 8 / 9 / 10 / 11** —— 文档与一致性清理，可批量做；顺手把 deadnix 加进工具集。
4. **问题 1 / 2** —— 同源，暂缓处理。需先弄清 den 里 home scope 的正确写法（三种候选写法均已证伪），**确认后一并处理**；在此之前不单独给问题2打 `key` 补丁，避免掩盖问题1的报错信号。
