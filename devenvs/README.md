# devenvs

项目级开发环境（devenv）。锁定与工具链的取舍见
[对应 ADR](docs/adr/0001-devenvs-locking-and-toolchain.md)。

## 概念与边界

**Global Dev Env**：home 层常驻的开发工具集合，不随目录变化；语言工具由
[`trait/dev/lang/`](../modules/aspects/trait/dev/lang/) 管理。统一使用此名称，避免含义更宽的“全局环境”或“home 环境”。
与 Project Dev Env 独立配置；项目环境激活后覆盖 `CC` / `CXX` / `CLANGD_FLAGS` 等变量，
Global 一侧不需要知道项目环境的存在。

**Modular Dev Env**：通用、可参数化的开发环境单元，如 cpp / cuda / python；由 Project Dev Env
组合使用，自身不作为目录绑定的激活入口。统一使用此名称，避免 Env Module、语言环境、devenv 模块。

**Project Dev Env**：绑定一个具体代码仓的开发环境，由若干 Modular Dev Env 与该仓特有配置组成，
是绑定到目录上激活的单元。版本固定方式见[锁定](#锁定)。统一使用此名称，避免 Project Env、项目 devenv、代码仓环境。

**插件（Plugin）**：本文专指 Modular Dev Env 上可选的附加工具组，如 cpp 的 ccache、cuda 的 nccl，
以开关或列表声明；统一称插件，避免扩展、addon。

**分析模式（Analysis Mode）**：Project Dev Env 对特定工具链提供代码分析能力的状态，包括 LSP
所需的头文件、编译参数与类型信息，该工具链的构建与测试不在此模式的支持范围内。避免称为阅读模式、只读模式。

**构建模式（Build Mode）**：Project Dev Env 对特定工具链提供编译与测试能力的状态。避免称为完整模式。

模式由模块根据平台条件给出，Project Dev Env 消费模块提供的事实。例如 `aor.env.cuda.buildable`
描述 CUDA 工具链的构建能力；macOS 上 CUDA 项目进入分析模式，不代表该平台上的 C++ 或 Python 项目都只能分析。

## 目录结构

```
devenvs/
├── modules/     Modular Dev Env：cpp / cuda / python / cutlass，选项在 aor.env.<name>
├── projects/    Project Dev Env：一个代码仓一个目录
└── docs/adr/    开发环境的决策记录
```

cutlass 既是模块也是项目：`modules/cutlass` 给 kernel 项目提供锁定版本的头文件路径与 CuTe DSL 的 editable
安装，`projects/cutlass` 是 cutlass 自己的开发环境（模块指向自己的 checkout）。

## 绑定一个代码仓

```console
cd ~/repos/flash-attention
devenv-deploy flash-attention   # = devenv --from path:~/Infra/devenvs/projects/flash-attention allow
```

之后进入这个目录（或子目录）时，devenv 的 shell hook 会自动激活环境，项目里不放任何配置文件。
devenv 生成的 `.devenv/` 和 `devenv.lock` 已由 `devenv-deploy` 写进 `.git/info/exclude`。它们只是缓存，
删掉后会重新生成，结果不变。

编辑器要从激活后的 shell 里启动，才能拿到 `CLANGD_FLAGS`、venv 等环境。VSCode（尤其 Remote-SSH）的扩展进程
不经过 shell hook，所以环境启用了 cpp 模块时，`devenv-deploy` 会把 `clangd.path`（指向 `.devenv/profile/bin/clangd`）
和 `clangd.arguments`（取自 `CLANGD_FLAGS`）合并进 `.vscode/settings.json`，并写进 `.git/info/exclude`。
已绑定的仓库重新执行一次 `devenv-deploy <name>` 即可补上。这种绑定方式下项目里没有 `.envrc` / `devenv.nix`，
direnv 和 devenv 的 VSCode 扩展都不会生效，不要装它们。

常用命令：

```console
devenv test                    # 按平台验收：Linux 构建并跑测试，macOS 检查 clangd/basedpyright
devenv tasks run <task>        # 例如 fa2:build、fa:compdb
devenv tasks list
devenv -s aarch64-linux eval aor.env.cuda.home   # 跨平台求值检查（不构建）
```

## 锁定

锁定以 Infra 里的内容为准：

- `projects/<name>/devenv.yaml` 中所有 input 都写死到具体 rev；
- Python 依赖记录在 `projects/<name>/pyproject.toml` 与 `uv.lock`。

升级流程：改 rev 或 pyproject，在 `projects/<name>/` 下执行 `uv lock`，提交。

darwin 上的 CUDA 头文件只能从 `cache.nixos-cuda.org` 替换下载，无法在本机构建。升级 nixpkgs rev 前，
先确认这个 cache 里已有对应的 `cudaPackages`。

## 新建 Project Dev Env

1. 新建 `projects/<name>/devenv.yaml`：nixpkgs 写死 rev，按需 import `../../modules/<m>`。
   用 cutlass 的 kernel 项目再声明一个 input：`cutlass: { url: github:NVIDIA/cutlass/<rev>, flake: false }`，
   `aor.env.cutlass.src` 默认就取它；上游已 vendor 子模块的项目把 `src` 指向子模块。
2. 新建 `projects/<name>/devenv.nix`：设置 `aor.env.<m>.*`，再补上该仓库特有的 env 和 tasks，以及 `enterTest`。
   `enterTest` 按 `config.aor.env.cuda.buildable` 等模块给出的事实区分模式，自己不写平台判断。
3. 有 Python 依赖时：新建 `pyproject.toml`（`[tool.uv] package = false`），把
   `aor.env.python.project` 设为 `toString ./.`，然后执行 `uv lock`。
4. 在代码仓目录里执行 `devenv-deploy <name>`，再执行 `devenv test`。

## 新建 / 修改 Modular Dev Env

- 一个模块一个目录（`modules/<m>/devenv.nix`），选项挂在 `aor.env.<m>` 下，形状为
  `enable` / `version` / `plugins` 加上模块自己的字段。
- 平台降级是模块的责任：当前平台不支持的插件直接跳过，不能让求值失败。分析模式下要提供 LSP 所需的东西。
- 这些模块只供本仓库内部使用，选项名可以随时修改。
