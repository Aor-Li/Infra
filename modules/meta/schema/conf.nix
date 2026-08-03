# 全局 schema 入口。
#
# den 会把 den.schema.conf 同时 import 进 host / user / home 三种实体，所以这里只
# 放「三种实体都成立」的东西；只属于某一种实体的选项去 host.nix / home.nix / user.nix。
{ ... }:
{ }
