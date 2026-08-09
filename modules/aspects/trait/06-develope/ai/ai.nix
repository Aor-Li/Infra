# 关掉它你会失去：所有 AI 工具及其共享配置。
#
# 分三块，加东西之前先想它属于哪一块：
#   agent/   每个工具一份，只放它自己认的东西（本体 + 私有路径的接线）
#   mine/    共享资产 · 自己写的，链回仓库，改完即刻生效
#   vendor/  共享资产 · 第三方，走 flake input，版本由 flake.lock 钉住
#
# 共享资产统一先落到中立的 ~/.agents/，各 agent 再从那里拉到自己认的路径——
# 这样加一个 agent 只动 agent/ 下的一个文件，加一份资产只动 mine/ 或 vendor/。
{ den, ... }:
{
  den.aspects.dev.ai.includes = [
    den.aspects.dev.ai.agent
    den.aspects.dev.ai.mine
    den.aspects.dev.ai.vendor
  ];
}
