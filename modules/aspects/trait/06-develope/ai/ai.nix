# 关掉它你会失去：所有 AI 工具及其共享配置。
#
# 分三块，加东西之前先想它属于哪一块：
#   agent/   每个工具一份，只放它自己认的东西（本体 + 私有路径的接线）
#   skill/   共享 skill：自己写的在 mine/，第三方走 flake input
#   prompt/  共享 prompt：只有自己写的
#
# 共享资产统一先落到中立的 ~/.agents/，各 agent 再从那里拉到自己认的路径——
# 这样加一个 agent 只动 agent/ 下的一个文件，加一份资产只动 skill/ 或 prompt/。
{ den, ... }:
{
  den.aspects.dev.ai.includes = [
    den.aspects.dev.ai.agent
    den.aspects.dev.ai.skill
    den.aspects.dev.ai.prompt
  ];
}
