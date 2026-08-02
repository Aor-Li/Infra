# Den-Infra

个人 Nix flake 配置，统一管理多台设备的 **NixOS / nix-darwin / WSL** 系统与 **home-manager** 家目录环境。

## 整体架构

- **dendritic 模式**：基于 [`flake-parts`](https://github.com/hercules-ci/flake-parts)，通过 [`import-tree`](https://github.com/denful/import-tree) 自动导入 `modules/` 下的**所有** `.nix` 文件，无需手动维护 `imports` 列表。
- **`flake.nix` 自动生成**：根 [`flake.nix`](flake.nix) 顶部标注 `DO-NOT-EDIT`，其 `inputs` 块由 [`flake-file`](https://github.com/vic/flake-file) 汇总各模块声明的 `flake-file.inputs` 生成。修改依赖后用 `nix run .#write-flake` 重新生成。
- **`den` 框架**：借助 [`den`](https://github.com/vic/den) 的 dendritic 模块，用 host / user / home 的抽象来组织多设备配置。

## 目录结构

```
modules/
├── profile.nix     # 声明所有 host / user / home（设备清单，见下表）
├── flakes/         # 配置 flake 本身：外部 input + 顶层 flakeModule（见该目录 README）
├── metas/          # den 的 schema 定义（host / user 的选项，如 virt / role / distro）
└── aspects/        # 实际配置内容
    ├── entity/     # 具体实体：各 host、user 的定义
    └── feature/    # 可复用特性：nix 设置、系统核心、按环境区分的模块等
```

## 设备清单

在 [`modules/profile.nix`](modules/profile.nix) 中定义：

| 主机 | 平台 | 环境 | 角色 | 系统 |
| --- | --- | --- | --- | --- |
| Enten | x86_64-linux | physical | desktop | nixos |
| Magatsumi | aarch64-darwin | physical | laptop | darwin |
| Kuregumo | aarch64-linux | virtual | laptop | nixos |
| Kumeyuri | x86_64-linux | wsl | desktop | nixos |
| Tobimune | x86_64-linux | physical | server | nixos |

## 常用命令

```console
# 修改 flake 依赖后，重新生成根 flake.nix
nix run .#write-flake

# 更新 den input
nix flake update den
```
