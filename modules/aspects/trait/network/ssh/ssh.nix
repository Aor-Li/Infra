# 关掉它你会失去：ssh 的客户端配置（~/.ssh/config）与 sshd。
# remote/ 下的各台远程机器不在这里汇总：能连哪台由 entity 显式 include。
{ den, ... }:
{
  den.aspects.network.ssh.includes = [
    den.aspects.network.ssh.client
    den.aspects.network.ssh.server
  ];
}
