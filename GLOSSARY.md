# Infra

个人机器与开发环境的声明式配置。本文件只记术语；结构与归属规则见 `AGENTS.md`。

## Dev Env

**Global Dev Env**:
home 层常驻的开发工具集合，任何 shell 里都在，不随目录变化。
_Avoid_: 全局环境、home 环境

**Modular Dev Env**:
通用、可参数化（版本 + 插件）的开发环境单元，如 cpp / cuda / python；自身不可激活，只能被 Project Dev Env 组合。
_Avoid_: Env Module、语言环境、devenv 模块

**Project Dev Env**:
绑定一个具体代码仓、版本全部锁定的开发环境，由若干 Modular Dev Env 加该仓特有配置组成；唯一能绑定到目录上激活的一类。
_Avoid_: Project Env、项目 devenv、代码仓环境

**插件（Plugin）**:
Modular Dev Env 上可选的附加工具组（如 cpp 的 ccache、cuda 的 nccl），以开关或列表声明。
_Avoid_: 扩展、addon

**分析模式（Analysis Mode）**:
Project Dev Env 在不具备构建条件的平台上的能力等级：只提供 LSP 读懂代码所需的头文件、编译参数与类型信息。
_Avoid_: 阅读模式、只读模式

**构建模式（Build Mode）**:
Project Dev Env 在具备条件的平台上的能力等级：能编译并运行测试。模式由平台条件决定，不由用户切换。
_Avoid_: 完整模式
