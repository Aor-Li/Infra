# 关掉它你会失去：Home Manager 管理的 SSH 客户端配置，以及首次切换时对手写配置的备份。
# 目标由 entity 的 provides.ssh 显式接入，不再全局读取 config.local / config.d/*。
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
      };

      # 一次性迁移：在 checkLinkTargets 之前把手写的 ~/.ssh/config 改名成 config.local。
      # 不做的话，host 上它会被 backupFileExtension 挪成 config.hm-backup，
      # standalone home 上则直接激活失败。备份供迁移参考，不自动 Include；先注册需要的目标。
      # 已是 symlink 或 config.local 已存在时什么都不做。
      home.activation.sshConfigToLocal = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        if [ -f "${dir}/config" ] && [ ! -L "${dir}/config" ] && [ ! -e "${dir}/config.local" ]; then
          run mv $VERBOSE_ARG "${dir}/config" "${dir}/config.local"
        fi
      '';
    };
}
