# 全局 schema 入口。
#
# den 会把 den.schema.conf 同时 import 进 host / user / home 三种实体，所以这里只
# 放「三种实体都成立」的东西；只属于某一种实体的选项去 host.nix / home.nix / user.nix。
#
# 每项能力一行 import，实现留在各自目录里——这个文件应该一直短到能一眼看完。
{ ... }:
{
  imports = [
    # aspect 自带的类型化配置项：aspect 用 `settings` 声明 mkOption，实体在同一路径
    # 上填值，aspect 再用 `{ settings, ... }` 读回来。
    ../_aspect-settings
  ];
}
