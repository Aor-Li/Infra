# 把本目录（ai/）下的资产挂进 $HOME 的公共接线。
#
# 一律走 out-of-store symlink 而不是 store：skill、全局指令、hook 是要和 agent
# 一起反复改的内容，进了 store 就是只读，改一个字都要 rebuild。out-of-store 下
# 改完即刻生效，同时仍在 git 里受版本管理、跨机器一致。
#
# 仓库路径只写在这一处（structure.md §7 想要的全局 repoRoot / mkRepoLink 还没
# 落地），移动 ai/ 目录时只改这里。
{ config }:
let
  self = "${config.home.homeDirectory}/Infra/modules/aspects/trait/06-develope/ai";
in
path: config.lib.file.mkOutOfStoreSymlink "${self}/${path}"
