# 关掉它你会失去：sshd——server 角色的 host 能被远程登录（纯密钥）。
{
  # 静态 attrset，host 在 class 层要（见 system/platform/mac.nix 的说明）。
  den.aspects.network.ssh.server.nixos =
    { host, lib, ... }:
    {
      services.openssh = {
        # sshd 服务端只对 server 角色默认开启；其余 host 可在自己的
        # entity 文件里 override 打开。
        enable = lib.mkDefault (host.role == "server");

        # 基础加固：纯密钥登录，关掉密码 / 键盘交互 / root 登录。
        # 全用 mkDefault，个别 host 需要时仍可放宽。
        settings = {
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = lib.mkDefault false;
          PermitRootLogin = lib.mkDefault "no";
        };
      };
    };
}
