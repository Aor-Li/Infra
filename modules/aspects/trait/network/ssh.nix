{ ... }:
{
  den.aspects.network.ssh =
    { host, ... }:
    {
      nixos =
        { lib, ... }:
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
    };
}
