# 问：这台机器常驻提供什么？——不进基线，由 entity 按需 include 具体叶子。
{ den, ... }:
{
  den.aspects.service.includes = [
    den.aspects.service.remote
  ];
}
