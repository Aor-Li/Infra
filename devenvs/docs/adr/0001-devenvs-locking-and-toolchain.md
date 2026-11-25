# devenvs：锁定以 Infra 为准，nix 管工具链、uv 管 Python 包、libcuda 来自宿主机

Project Dev Env 用 devenv 的 `--from` 绑定到上游仓库目录，上游仓库里不放任何配置文件。但 devenv
会把 `devenv.lock` 和 `.devenv/` 写在被绑定的目录里。所以锁定不依赖那份 lock 文件，而是靠 Infra
里的两样东西：`devenv.yaml` 里写死的 input rev，以及 `pyproject.toml` + `uv.lock`。项目目录里的
`devenv.lock` 只是缓存。

工具链按来源拆成三块：

- **nix**：编译器、nvcc、CUDA 头文件，以及 Python 解释器本身。
- **uv**：按 PyTorch index 安装 torch 等 Python 包。这和上游 CI 一样（例如 flash-attention 用的是
  torch 的 cu130 wheel）；同一份通用锁在 Linux 上解析成 CUDA 版，在 macOS 上解析成 CPU 版。
- **宿主机**：`libcuda` 等驱动库必须与内核模块版本一致，所以只把这几个库软链进 `LD_LIBRARY_PATH`，
  不引入宿主机的其它系统库。

## Considered Options

- **flake-parts devShells 加 nix-direnv**：lock 能集中放在 Infra，但 uv/venv、libcuda 接入、tasks
  都得自己写，每个项目还要放一个 `.envrc`。没有选它。
- **torch 也从 nixpkgs 拿（cudaSupport）**：版本很难对齐上游 CI 的矩阵，还要依赖 CUDA cache
  或者自己编译 torch。没有选它。
- **直接用宿主机的 `/usr/local/cuda`**：最省事，但 nix 侧不可复现，mac 上也拿不到同一套头文件。
  没有选它。

## Consequences

- **mac 上的分析模式**：CUDA 头文件以及 host 侧的 libstdc++/glibc 都取自 x86_64-linux 包集合，
  只能从 `cache.nixos-cuda.org` / `cache.nixos.org` 下载现成的，不能在本机构建。所以升级 nixpkgs
  rev 前，要先确认这些 cache 里已有对应的包。
- **clang 的 host 目标**：分析模式下 clang 把 host 当成 x86_64-linux。这样 clangd 在 mac 上看到的
  头文件和宏，和 philo 上 nvcc + gcc 编译时一致。
