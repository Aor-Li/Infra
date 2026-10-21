# Infra

个人 Nix flake 配置，统一管理多台设备的 **NixOS / nix-darwin** 系统与 **home-manager** 家目录环境
（nixos / darwin 主机上 home-manager 作为系统模块运行，随系统 switch 一起生效；
没有 den host 的机器才用 standalone home）。

## 整体架构

- **dendritic 模式**：基于 [`flake-parts`](https://github.com/hercules-ci/flake-parts)，通过 [`import-tree`](https://github.com/denful/import-tree) 自动导入 `modules/` 下的**所有** `.nix` 文件，无需手动维护 `imports` 列表。
- **`flake.nix` 自动生成**：根 [`flake.nix`](flake.nix) 顶部标注 `DO-NOT-EDIT`，其 `inputs` 块由 [`flake-file`](https://github.com/vic/flake-file) 汇总各模块声明的 `flake-file.inputs` 生成。修改依赖后用 `nix run .#write-flake` 重新生成。
- **`den` 框架**：借助 [`den`](https://github.com/vic/den) 的 dendritic 模块，用 host / user / home 的抽象来组织多设备配置。

## 目录结构

完整的归属规则见 [`AGENTS.md`](AGENTS.md)。

```
modules/
├── inventory.nix   # 设备清单：声明所有 host / user / home（见下表）
├── flakes/         # 配置 flake 本身：外部 input + 顶层 flakeModule（见该目录 README）
├── meta/           # 框架层：schema（host / home 的选项）与 aspect-settings
└── aspects/
    ├── default/    # 基线：所有实体都吃到的 den.default
    ├── entity/     # 谁：hosts/ 与 users/，只声明身份 + include 哪些 trait
    └── trait/      # 配什么：nix / system / network / security / desktop / dev / app / service
```

## 设备清单

在 [`modules/inventory.nix`](modules/inventory.nix) 中定义：

| 主机 | 平台 | virt | 角色 | 系统 | include 的可选面向 |
| --- | --- | --- | --- | --- | --- |
| Enten | x86_64-linux | none | desktop | nixos | desktop + app |
| Magatsumi | aarch64-darwin | none | laptop | darwin | aerospace + app |
| Kumeyuri | aarch64-darwin | none | laptop | darwin | aerospace + app |
| Kuregumo | aarch64-linux | vm | laptop | nixos | desktop + app |
| Tobimune | x86_64-linux | none | server | nixos | （无） |
| aor@philo | x86_64-linux | — | standalone home | Ubuntu | （无） |

## 常用命令

```console
# 首次激活一台机器 / 一个 home
./scripts/bootstrap.sh Enten          # nixos-rebuild（home-manager 随系统一起激活）
./scripts/bootstrap.sh aor@philo      # 只有 home-manager

# 修改 flake 依赖后，重新生成根 flake.nix
nix run .#write-flake

# 更新 den input
nix flake update den

# 静态检查
nix run nixpkgs#deadnix -- modules
nix run nixpkgs#statix -- check modules
nix run nixpkgs#nixfmt -- --check $(git ls-files 'modules/*.nix')
```
