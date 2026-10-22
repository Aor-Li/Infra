# devenvs

项目级开发环境（devenv）。术语见仓库根的 `GLOSSARY.md`，取舍见 `docs/adr/0001-devenvs-locking-and-toolchain.md`。

```
devenvs/
├── modules/     Modular Dev Env：cpp / cuda / python，选项在 aor.env.<name>
└── projects/    Project Dev Env：一个代码仓一个目录，版本全部锁定
```

## 绑定一个代码仓

```console
cd ~/repos/flash-attention
devenv-deploy flash-attention   # = devenv --from path:~/Infra/devenvs/projects/flash-attention allow
```

之后进入这个目录（或子目录）时，devenv 的 shell hook 会自动激活环境，项目里不放任何配置文件。
devenv 生成的 `.devenv/` 和 `devenv.lock` 已由 `devenv-deploy` 写进 `.git/info/exclude`。它们只是缓存，
删掉后会重新生成，结果不变。

编辑器要从激活后的 shell 里启动，才能拿到 `CLANGD_FLAGS`、venv 等环境。

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
