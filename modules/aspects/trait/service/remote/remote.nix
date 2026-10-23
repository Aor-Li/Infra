# 问：从别的机器远程操作这台机器的哪种方式？
#
# 两个成员平台不重叠（sunshine 只有 nixos class，rustdesk 只有 darwin class），
# entity 按需 include 叶子，而不是整组。
{ den, ... }:
{
  den.aspects.service.remote.includes = [
    den.aspects.service.remote.rustdesk
    den.aspects.service.remote.sunshine
  ];
}
