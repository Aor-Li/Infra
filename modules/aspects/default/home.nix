# home-manager 侧的公共基线：给每个 HM 用户提供 config.lib.{owner,repo}。
#
# 两个来源同一份逻辑：host 内嵌的 HM 用户读 user 实体，standalone home（den.homes）
# 读 home 实体，选项定义见 meta/schema/identity.nix。
#
# config.lib.owner —— { fullname; email; }，git 等需要「我是谁」的地方从这里读。
#
# config.lib.repo —— 所有「链回仓库工作区」的 out-of-store symlink 都从这里出发，
# 仓库路径（repoRoot，默认 ~/Infra）与模块在仓库里的相对位置都不用手写：
#
#   xdg.configFile."lazyvim".source = config.lib.repo.link ./_lazyvim;
#
# `link` 接受模块文件旁边的相对路径（求值时已是 /nix/store/<self>/modules/… 的 store 路径），
# 去掉 flake 自身的 store 前缀就得到仓库内相对路径，再接到 repoRoot 下。目录移动时链接
# 自动跟着走，不再需要「路径写死，移动本目录时必须同步改这里」这类注释。
{ inputs, lib, ... }:
let
  base = owner: {
    homeManager =
      { config, ... }:
      let
        root = if owner.repoRoot != null then owner.repoRoot else "${config.home.homeDirectory}/Infra";
        relative = path: lib.removePrefix "${inputs.self}/" (toString path);
      in
      {
        lib.owner = { inherit (owner) fullname email; };
        lib.repo = {
          inherit root;
          # 仓库内任意路径 → 指向工作区同一位置的 out-of-store symlink
          link = path: config.lib.file.mkOutOfStoreSymlink "${root}/${relative path}";
          # 仓库内路径的字符串形式（给需要路径而不是 symlink 的地方用）
          path = path: "${root}/${relative path}";
        };
      };
  };
in
{
  den.schema.user.includes = [ ({ user, ... }: base user) ];
  den.schema.home.includes = [ ({ home, ... }: base home) ];
}
