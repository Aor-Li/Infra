# 配置结构与归属原则

本仓库 `modules/` 下的组织方式，以及"新增一个东西该放哪"的判定规则。
新增、移动任何配置前先读本文；与本文冲突的改动要么改代码，要么先改本文。

## 0. 分层

```
modules/
├── flakes/        flake 自身：外部 input 与顶层 flakeModule
├── meta/          框架层：den 自己的形状
│   ├── schema/        实体的选项定义（conf 全局 / host / user / home）
│   └── _aspect-settings/  见 6.1，由 schema/conf.nix 显式 import
├── inventory.nix  设备清单：声明所有 host / user / home
└── aspects/
    ├── default/   基线：所有实体都吃到的 den.default
    ├── entity/    谁：hosts/ 与 users/，只声明身份 + include 哪些 trait
    └── trait/     配什么：唯一定义能力的地方
```

`entity` / `trait` 这一层**不参与属性路径**——`trait/dev/dev.nix` 声明的是
`den.aspects.dev`，`entity/hosts/Enten.nix` 声明的是 `den.aspects.Enten`。
它是给人看的分类标签，改名是零成本的纯 rename。

**没有 preset 层。** 组合决策只有两个来源：

- 全体适用 → `schema/config/default.nix` 的 `den.default.includes`
- 个体差异 → `entity/hosts/*.nix` 里显式 include

方向性硬规则：**基线只放真正全体适用的东西，可选部分一律由 entity 加进来，
绝不"全体加 + 个别减"**。Nix 的 module 系统里 include 容易、移除难，一旦基线
塞了可选项，个别机器只能靠 `mkIf` 打补丁。

重新引入 preset 的触发条件（满足其一再考虑）：机器数超过 8–10 台；出现无法从
任何机器属性推导的命名组合（如"公司机 vs 私人机"）；仓库要对外提供可复用入口。

## 1. 四条不变式

**① 属性路径 == 目录路径。** 在 `trait/` 内部，aspect 名是 API、目录是它的物理
地址，逐段一致。移动目录 = 改 API，必须一起改。

**② 同一层的兄弟，必须是同一个问题的答案。** 每个中间目录都要能写出它向下提的
那个问题（见第 2 节的「问：」）。写不出来的层就是杂物筐，删掉。

**③ 一个程序只有一个 owner**，由"关掉它我期待失去什么"决定，而不是由它的实现
形式决定。ghostty 是 GUI 程序，但关掉它是想失去终端 → 归 dev，图形依赖用门控
表达，不用目录表达。

**④ 跨切面维度不进目录树。** 平台、主机角色、系统层/home 层、主题配色、密钥
来源——这五样正交于功能分类，一旦建目录就会和功能树打架。表达方式见第 5 节。

## 2. trait 结构

顶层问：**这台机器的哪个面向？** 判定顺序从上往下——先问"是不是在配置 nix
自己"，再问"是不是登录之前就要成立"，最后才轮到面向用户的三个。

```
trait/
├── nix/                    问：nix 工具链的哪一部分？
│   ├── nix.nix                 汇总
│   ├── conf.nix                substituters / features / gc / optimise
│   ├── home-manager.nix        集成方式
│   ├── nix-ld.nix
│   └── tool/                   nh / nix-index / nix-output-monitor
│
├── system/                 问：登录之下的哪一层？
│   ├── boot/                   bootloader / kernel / initrd
│   ├── hardware/               显卡 / 音频 / 蓝牙 / 打印机 / 外设
│   ├── platform/               ★ 唯一的平台例外，见 5.1
│   │   ├── nixos.nix
│   │   ├── darwin.nix
│   │   └── wsl.nix
│   ├── locale.nix              时区 / i18n
│   ├── fonts.nix               ★ 终端与桌面共享的资源，故在 system 而非 desktop
│   ├── xdg.nix
│   └── power.nix               休眠 / 电源策略
│
├── network/                问：连通性的哪一层？
│   ├── core.nix                hostname / DNS / NetworkManager
│   ├── firewall.nix
│   ├── ssh.nix                 客户端配置与 sshd
│   ├── vpn/                    tailscale / wireguard / 公司 VPN
│   └── proxy.nix               ★ host 所有权差异的着力点之一
│
├── security/               问：谁能访问什么？
│   ├── secrets/                sops：密钥分发的唯一来源
│   ├── auth.nix                sudo / polkit / PAM / 生物识别
│   ├── agent.nix               gpg-agent / ssh-agent / yubikey
│   └── hardening.nix
│
├── desktop/                问：图形会话的哪一部分？
│   ├── session/                compositor(niri) / display manager / portal
│   ├── shell/                  顶栏 / 通知 / launcher（quickshell + dank）
│   ├── input/                  输入法(fcitx5) / 键鼠 / 手势
│   └── appearance/             主题 / 光标 / 壁纸 / GTK-Qt 一致性
│
├── dev/                    问：你与代码交互的哪一环？
│   ├── shell/                  交互环境：拿到提示符之后改变你敲命令方式的东西
│   │   ├── shell.nix               bash/fish/zsh 本体、通用别名、会话变量
│   │   ├── prompt/                 starship
│   │   ├── terminal/               ghostty / wezterm
│   │   ├── multiplexer/            tmux / zellij / herdr
│   │   └── util/                   带 shell 集成的 CLI：zoxide / atuin / fzf / eza / yazi
│   ├── editor/                 写代码的地方（EDITOR/VISUAL 在 editor.nix 统一定义）
│   │   ├── neovim/                 + _lazyvim/
│   │   ├── helix.nix
│   │   └── vscode.nix
│   ├── lang/                   一语言一叶子：工具链 + LSP + formatter + debugger
│   │   └── nix.nix / c.nix / python.nix / rust.nix / go.nix …
│   ├── vcs/                    git / lazygit / gh / delta / 签名
│   ├── env/                    项目级环境：direnv / devenv / 开发容器 / 模板
│   ├── ops/                    运维客户端：kubectl / k9s / terraform / 云 CLI
│   ├── ai/                     claude-code / codex / MCP / agent 配置
│   └── tool/                   独立 CLI：调用完就结束、不与上面任何一环耦合
│
├── app/                    问：这是哪一类日常应用？
│   ├── browser/
│   ├── note/                   obsidian
│   ├── comm/                   聊天 / 邮件
│   ├── media/                  播放器 / 图像 / 音乐
│   └── game/
│
└── service/                问：这台机器常驻提供什么？
    ├── container.nix           docker / podman daemon
    ├── remote/                 sunshine / rustdesk
    ├── storage/                syncthing / nfs / samba
    ├── web/                    caddy / nginx
    ├── media/                  jellyfin / *arr
    ├── monitor/
    └── backup/
```

几处易混边界：

- **`dev/shell/util/` vs `dev/tool/`**：它是否安装 shell 集成（init hook / 补全 /
  别名 / keybind）？是 → util，否 → tool。yazi 带 `y` 函数 → util；jq → tool。
- **`dev/env/container` vs `service/container`**：跑开发容器 → dev；托管常驻服务
  → service。同一个包按用途归属。
- **`desktop/` vs `app/`**：desktop 是会话基础设施（compositor / 外壳 / 输入法），
  app 是你用的软件。niri 属于前者，obsidian 属于后者。

## 3. 单向依赖

```
nix → system → network / security → desktop → dev / app / service
```

高层可以消费低层提供的东西（dev 用 `security/secrets` 的密钥、`system/fonts` 的
字体），**低层永远不知道高层存在**——`system/fonts.nix` 里不许出现"因为 nvim
需要所以装 nerd-font"这种理由。

有了这条，共享资源"上移到哪"就没有歧义：上移到所有消费者的共同下游。

## 4. 交叉特性的判定

交叉分三种，解法不同。

**① 假交叉：目的 vs 形式。** 程序同时具有两种属性，但只有一种是它的目的，另一
种是实现形式或前提条件。IDE 是 GUI 应用（形式），但你要的是编辑器（目的）。
→ 按目的归属，形式用门控表达，**不拆**。九成的交叉属于这一类。

**② 真交叉：两套互不相干的配置恰好来自同一个包。** docker（开发容器 vs 托管
服务）、ssh（客户端 vs sshd）、syncthing（守护进程 vs 托盘 GUI）。
判据：这两份配置我会在不同时候、为不同理由去改吗？
→ 按**消费者**拆成两个 trait。**共享一个包不是罪，共享一段配置才是。**

**③ 共享资源：谁都在用、谁都不拥有。** 字体、CA 证书、主题、字典。
→ 上移到所有消费者的共同下游（见第 3 节）。

判定顺序：

1. "关掉它我期待失去什么？"——答案唯一 → 归那里，结束。
2. 答案有两个，但其中一个是前提条件（要有图形/要联网）→ 归目的那边，前提用门控。
3. 答案真是两个平等的目的 → 拆成两个 trait，按消费者划分。
4. 谁都在用、谁都不拥有 → 上移。

判不出来时的 tiebreaker：**看它的配置引用了谁**，配置的引力方向就是归属方向。

### 一个程序横跨多个环时

IDE 把 editor + lang + vcs + ai 打包在一个程序里。此时用第二条原则：

> **分类的单位是"你会一起修改的东西"，不是功能语义。**

vscode 的 extensions 与 settings 整个住在 `dev/editor/vscode.nix`，哪怕里面有
rust-analyzer 和 gitlens。不要为了分类纯洁性切成四份塞进 lang/vcs/ai——那会让
"改一下 IDE"变成翻四个文件。

但底层能力要分开：**程序自己的配置**留在自己的 trait，**被共享的底层工具**归
它自己的 trait，程序只假设它存在。`vscode.nix` 里写 `extensions = [ rust-analyzer ]`，
不写 `packages = [ rustc ]`——rustc 属于 `dev/lang/rust.nix`。

### 案例表

| 东西 | 归属 | 规则 |
|---|---|---|
| vscode / JetBrains | `dev/editor/` | ① 目的是编辑器，GUI 是形式 |
| ghostty | `dev/shell/terminal/` | ① 目的是终端 |
| obsidian | `app/note/` | ① 关掉是失去笔记，不是失去开发能力 |
| firefox（含开发者工具） | `app/browser/` | ① 目的是浏览器 |
| docker | `dev/env/` + `service/` 各一份 | ② 两套配置，两个消费者 |
| syncthing | `service/storage/` + 托盘归 `app/` | ② 同上 |
| ssh | 客户端 `network/`、sshd `service/` | ② 同上 |
| 字体 | `system/fonts` | ③ 终端与桌面共享 |
| CA 证书 | `security/` | ③ 被网络/浏览器/开发工具共享 |
| catppuccin 配色 | `home.theme` 选项 | ③ 极致形态：上移到不再是 trait |

## 5. 不该建的目录

这几样将来一定会想建，都不要建：

| 想建的 | 正确位置 |
|---|---|
| `theme/` `catppuccin/` | `home.theme` 选项，各程序自己读 |
| `darwin/` `wsl/` 作为顶层 | trait 内的 class + `host.distro` / `host.virt` 门控 |
| `server-tools/` `laptop/` | entity 里显式 include |
| `home/` 与 `system/` 两棵平行树 | 同一 trait 内的 `homeManager` / `nixos` class |
| `work/` `personal/` | `host.ownership` 派生的具体开关 + 目录级隔离（见 6） |

### 5.1 唯一的平台例外：`system/platform/`

边界卡死：**只放"只有这个平台才存在的东西"**（nixos-wsl 模块、darwin 的
`system.defaults`、Linux 特有内核参数），**不放"某个功能在这个平台上的写法"**。

ghostty 在 darwin 用 homebrew 装 —— 这条属于 `dev/shell/terminal/ghostty.nix`，
用 `darwin` class 表达。一旦 `platform/darwin.nix` 里出现 `homebrew.casks`，
分类就开始崩了。

## 6. 门控与选项

**系统层 vs home 层的硬规则**：系统层只装"没有 home-manager 也要能救机"的东西
（vim / curl / git / 基本网络工具），其余一律 home 层。没有这条，
`system/` 和 `dev/tool/` 会永远互相渗透。

**门控只回答"装了之后在这个平台/环境上怎么实现"**，不兼职回答"装不装"——后者
是 entity include 的活。

**选项管参数化差异，include 管增量能力：**

- 同一个 trait 在两种环境下取不同值（git 邮箱、代理地址、缓存源）→ 选项 + 门控
- 一整类东西只在某种环境下存在（VPN 客户端、内网 CA）→ entity 里显式 include

**新增 host 选项时，让它当"默认值的来源"，而不是让 trait 直接判断它。**
`host.ownership` 这类笼统属性不该被几十个 trait 直接 `mkIf`，否则第一次遇到例外
就无解。正确做法：

```nix
# schema/config/default.nix —— 由笼统属性推导具体开关
useProxy      = lib.mkDefault (config.ownership == "company");
allowAiAgents = lib.mkDefault (config.ownership == "personal");
```

trait 里写 `lib.mkIf host.useProxy`，不写 `mkIf (host.ownership == "company")`。
每一条都能被单台机器单独推翻，而不破坏整个抽象。

曾经的 `graphical` 是个反例：它铺在 5 个 trait 里当门控，却又只是"这是台桌面机"
的同义反复，最终被整体移除——桌面栈现在纯靠 entity 的 `includes` 决定（哪台机器
include `desktop` / `app`）。真正需要细粒度开关时用下面的 `settings`。

### 6.1 aspect 自带的选项：`settings`

上面那条只适用于**真正跨 trait 的笼统属性**（`role` / `distro` / `virt`）。一个
只有单个 trait 关心的开关不该往 host schema 上堆——它属于那个 trait 自己。

机制（实现见 `meta/_aspect-settings/`）：aspect 用 `settings` 声明 `mkOption`，
schema 把整棵 aspect 树按**同样的路径**镜像成一个强类型的 `settings` 选项，实体
填值，aspect 再从注入的 `settings` 参数读回来。

整个特性——保留字、声明侧的 schema 选项、消费侧的 policy 注入——都收在那一个
目录里，`meta/schema/conf.nix` 只用一行 import 引它。

```nix
# trait 侧：声明 + 消费都在自己文件里
den.aspects.system.power.sleep = {
  settings.neverSleep = lib.mkOption { type = lib.types.bool; default = false; };
  nixos = { settings, ... }: lib.mkIf settings.system.power.sleep.neverSleep { … };
};

# inventory 侧：个体差异
den.hosts.x86_64-linux.Tobimune.settings.system.power.sleep.neverSleep = true;
```

四条硬规则：

- **`settings` 是保留字，不能再有 aspect 叫这个名字。**（`nix.settings` 因此
  改名成 `nix.conf`。）撞名的症状是配置被静默 include 两次。
- **aspect 上的 `settings` 只是声明槽，填值一律走实体路径。** 把值直接写在
  aspect 上（`den.aspects.Tobimune.settings.… = true`）看起来很自然，但那棵镜像
  子树没有任何消费者，惰性求值永远不触发——不报错也不生效。
  `meta/_aspect-settings/lint.nix` 会在求值期把这种写法拦下来，并列出出错路径。
- **不给 `default` = 必填。** 装了这个 aspect 却没给值，直接求值失败——磁盘 ID、
  AS 号这类"必须由机器告诉我"的事实就该这样。有合理全局值的一律给 `default`。
- **`settings` 只能声明在静态 attrset 形态的 aspect 上。** 写成
  `den.aspects.x = { host, ... }: { … }` 的参数化 aspect，生成器看不进函数体。
  需要 `host` 就在 class 那一层要：`nixos = { host, settings, ... }: …`。

取值来源按**谁产出这份配置**决定，不做级联：

| pipeline | 读谁 |
| --- | --- |
| `nixosConfigurations` / `darwinConfigurations` | `host.settings` |
| `homeConfigurations` | `home.settings` |

所以系统层和 home 层都要用的开关，两边各写一次。这是刻意的——den 不会把 host
的值传给 standalone home，硬造一层级联只会让"这个值到底从哪来"变得不可查。

> home 侧受 [known-issues 问题 1](../docs/known-issues.md) 影响：同一 system 下
> 共用 den 用户名的多个 home 会串味。在那个 bug 修掉之前，`home.settings` 只能
> 全部写成一样的值，差异化开关一律走 host 侧。

**工作/个人的边界**（尚未落地，先记判据）：

- 公司的东西泄漏到个人侧有真实后果 → 新增 user（硬隔离，代价是切换摩擦）
- 无后果，但整台机器归公司 → `host.ownership` 属性
- 无后果，只是某些项目属于公司 → 目录级隔离（git `includeIf` + direnv）

公司特有的**内容**（内网域名、代理地址、CA、私有 registry）不进本仓库：开关和
引用点留在这里，内容走私有 flake input 或 sops。

## 7. 文件约定

- 目录 `X/` 的汇总点固定是 `X/X.nix`，**只写 `includes` 和该层所有子节点共享的
  配置**，不装单个程序的包。
- `_name/` 前缀表示**不参与 import-tree 自动导入**，两种用途，都与消费它的模块
  同目录：非 nix 载荷（`_lazyvim/`、dank 的 `*.kdl`），以及需要被显式 `import`
  的 nix 模块（`meta/_aspect-settings/`）。后者用于把一个自足的特性收成一个目录，
  让引用它的文件保持一行。
- **预留槽位**（`terminal/` `prompt/` `multiplexer/` `vpn/` `browser/`）即使只有
  一个文件也建目录——它们是 API 的一部分，加第二个成员时零改动。
  **松散分组**才适用"攒够 3 个再拆目录"。
- 每个 trait 文件开头一行注释写"关掉它你会失去什么"。写不出来 = 归错地方了。
- 仓库路径不要在各文件里各写一遍：用 home 层的 `repoRoot` 选项 + `mkRepoLink`
  helper 集中一处，目录移动时只改一个地方。
