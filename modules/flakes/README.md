# modules/flakes

本目录只存放**配置 flake 本身**的内容，即这套配置作为一个 Nix flake 所依赖的**外部输入（inputs）**与**顶层 flake-parts 模块（flakeModules）**。

这里**不**包含任何系统、用户或 home 的实际配置——那些属于 [`../aspects`](../aspects)、[`../meta`](../meta) 与 [`../inventory.nix`](../inventory.nix)。

> 仓库整体架构（dendritic 模式、`flake.nix` 自动生成等）见[根目录 README](../../README.md)。

## 本目录里放什么

每个文件对应一个 flake 层面的依赖 / 关注点，通常做两件事：

1. **声明 input**——通过 `flake-file.inputs.<name>` 告诉 `flake-file` 往生成的 `flake.nix` 里加入哪个输入；
2. **接入模块**——通过 `imports` 引入该 input 提供的顶层 flake-parts `flakeModule`，使其能力在整个 flake 中可用。

约定：**一个文件一个 input / 关注点**，文件名即该依赖的名字。

| 文件 | 声明的 input | 作用 |
| --- | --- | --- |
| [`dendritic.nix`](dendritic.nix) | `den` / `import-tree` / `flake-file` / `flake-parts` | 整套框架的地基：flake-parts、自动导入、flake.nix 生成器，以及 `den` 提供的 dendritic 模块 |
| [`nixpkgs.nix`](nixpkgs.nix) | `nixpkgs` | 固定 nixpkgs 到 `nixpkgs-unstable` 频道 |
| [`home-manager.nix`](home-manager.nix) | `home-manager` | 引入 home-manager 的 flakeModule，其 `nixpkgs` 跟随本仓库的 `nixpkgs` |
| [`darwin.nix`](darwin.nix) | `darwin`（nix-darwin） | darwin 主机的系统构建器：den 默认取 `inputs.darwin.lib.darwinSystem`，故 input **必须名为 `darwin`**。无 flakeModule 可引，只需声明 input |

## 边界：什么该放这里，什么不该

**放这里**：全局性、地基性的 input——被整套配置横向依赖、或提供框架级能力的输入（如上表）。

**不放这里**：**特性专属**的 input 与它所服务的特性**就近放在一起**，而不是集中到本目录。

例如 `nixos-wsl` 只在 WSL 场景用到，因此它的 input 声明与模块导入都写在
[`../aspects/trait/system/platform/wsl.nix`](../aspects/trait/system/platform/wsl.nix) 里，
而不放在本目录。

> 判断原则：如果一个 input 是「整个 flake 的地基 / 跨特性共享」，放本目录；
> 如果它「只服务某个具体特性」，就和那个特性放在一起。

## 新增一个 flake 依赖

1. 在本目录新建 `<name>.nix`（若为地基级依赖）；
2. 声明 `flake-file.inputs.<name>.url = "..."`，如需锁定 nixpkgs 加上 `inputs.nixpkgs.follows = "nixpkgs"`；
3. 若该 input 提供 flakeModule，在 `imports` 中引入（推荐用 `or { }` 兜底，避免 input 缺失时报错）；
4. 运行 `nix run .#write-flake` 重新生成根 `flake.nix`。
