{ inputs, ... }:
let
  # ---- secrets 存储位置约定 ----
  #
  # 密文（sops 加密的 yaml，可安全入库）与对应实体就近存放：
  #   系统级：entity/hosts/<hostName>/secrets.yaml
  #   用户级：entity/users/<userName>/secrets.yaml
  #
  # 解密后的明文落地位置沿用 sops-nix 默认值：
  #   系统级：/run/secrets/<name>       （tmpfs，重启即失）
  #   用户级：%r/secrets/<name>         （%r = XDG_RUNTIME_DIR）
  #
  # age 私钥（不入库，需手动放置）：
  #   系统级：/var/lib/sops-nix/key.txt
  #   用户级：~/.config/sops/age/keys.txt
  #
  # 密文文件尚不存在时用 pathExists 兜底不设 defaultSopsFile，
  # 避免 Nix 求值期因路径缺失而报错。
  entityDir = ../../../entity;
  hostSecretsOf = name: entityDir + "/hosts/${name}/secrets.yaml";
  userSecretsOf = name: entityDir + "/users/${name}/secrets.yaml";

  systemKeyFile = "/var/lib/sops-nix/key.txt";
in
{
  flake-file.inputs = {
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.security.secrets = {
    os =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        sopsFile = hostSecretsOf config.networking.hostName;
      in
      {
        environment.systemPackages = with pkgs; [
          age
          sops
        ];

        # 不依赖 ssh host key（多数主机已按角色关闭 sshd），改用显式 age 私钥。
        sops.age.keyFile = lib.mkDefault systemKeyFile;
        sops.age.sshKeyPaths = lib.mkDefault [ ];
        sops.gnupg.sshKeyPaths = lib.mkDefault [ ];

        sops.defaultSopsFile = lib.mkIf (builtins.pathExists sopsFile) sopsFile;
      };

    nixos.imports = [ inputs.sops-nix.nixosModules.sops ];
    darwin.imports = [ inputs.sops-nix.darwinModules.sops ];

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        sopsFile = userSecretsOf config.home.username;
      in
      {
        imports = [ inputs.sops-nix.homeManagerModules.sops ];

        home.packages = with pkgs; [
          age
          sops
        ];

        sops.age.keyFile = lib.mkDefault "${config.home.homeDirectory}/.config/sops/age/keys.txt";

        sops.defaultSopsFile = lib.mkIf (builtins.pathExists sopsFile) sopsFile;
      };
  };
}
