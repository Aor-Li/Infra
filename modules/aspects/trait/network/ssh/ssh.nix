# 关掉它你会失去：声明式 SSH 客户端配置，以及 NixOS 上按角色启用的 sshd 基础配置。
{ den, lib, ... }:
{
  den.aspects.network.ssh = {
    # entity 用构造器提供自己的连接 aspect；本 trait 不持有或自动 include 任何目标。
    provides.encryptedConfig = import ./_lib/encrypted-config.nix { inherit den; };
    provides.target = import ./_lib/target.nix { inherit den; };

    settings.targets = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            hostName = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "客户端访问地址；null 沿用目标定义。";
            };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "主别名的登录用户；null 沿用目标定义。";
            };
            port = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = "客户端访问端口；null 沿用目标定义。";
            };
            proxyJump = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "客户端跳板；null 沿用目标定义，none 表示直连。";
            };
            identityFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "客户端已有私钥的运行时路径字符串；null 沿用目标定义。";
            };
          };
        }
      );
      default = { };
      description = "已 include 的 SSH 目标的客户端参数覆盖；填值不会启用目标。";
    };

    includes = [
      den.aspects.network.ssh.client
      den.aspects.network.ssh.server
    ];
  };
}
