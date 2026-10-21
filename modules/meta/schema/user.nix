{ lib, ... }:
{
  # nixos / darwin 主机上的用户一律由 home-manager 模块管理：系统 switch 时 home 一起
  # 生效，不再单独 home-manager switch。standalone 只留给没有 den host 的机器（den.homes）。
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];
}
