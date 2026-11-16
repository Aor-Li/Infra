# 关掉它你会失去：由 home-manager 生成的 ~/.ssh/config，以及经它 Include 的各远程条目。
#
# ~/.ssh/config 本身只做 Include（ssh 对第一次取到的值生效，所以手写的排在前面，可覆盖）：
#   config.local  本机手写、不进仓库的条目。第一次 switch 时由原来手写的 ~/.ssh/config
#                 改名而来（见下面的 activation），之后继续在这里手写。
#   config.d/*    remote/ 下各 aspect 用 sops 解密落地的条目——里面是公司机器的地址，
#                 按 AGENTS.md 第 6 节不明文入库。
{
  den.aspects.network.ssh.client.homeManager =
    { config, lib, ... }:
    let
      dir = "${config.home.homeDirectory}/.ssh";
    in
    {
      programs.ssh = {
        enable = true;
        # 不要 HM 旧版那套 Host * 默认值（ControlMaster / HashKnownHosts …），
        # 行为与原来手写时一致：没写的就是 ssh 自己的默认。
        enableDefaultConfig = false;
        includes = [
          "config.local"
          "config.d/*"
        ];
      };

      # 一次性迁移：在 checkLinkTargets 之前把手写的 ~/.ssh/config 改名成 config.local。
      # 不做的话，host 上它会被 backupFileExtension 挪成 config.hm-backup（条目全部失效），
      # standalone home 上则直接激活失败。已是 symlink 或 config.local 已存在时什么都不做。
      home.activation.sshConfigToLocal = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        if [ -f "${dir}/config" ] && [ ! -L "${dir}/config" ] && [ ! -e "${dir}/config.local" ]; then
          run mv $VERBOSE_ARG "${dir}/config" "${dir}/config.local"
        fi
      '';
    };
}
