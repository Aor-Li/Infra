{
  # 静态 attrset，host 在 class 层要：写成 `{ host, ... }:` 的参数化 aspect 会在 host 与
  # host+user 两个上下文各展开一次，下面的 systemPath 这类 list 会被合并两遍。
  den.aspects.system.platform.mac.darwin =
    {
      config,
      host,
      lib,
      ...
    }:
    {
      # brew 追加在 PATH 末尾，nix 提供的同名程序优先。不用 homebrew.enable*Integration：
      # 它走 `brew shellenv`，会把 /opt/homebrew/bin 插到 PATH 最前面。
      environment.systemPath = lib.mkAfter [
        "${config.homebrew.prefix}/bin"
        "${config.homebrew.prefix}/sbin"
      ];

      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = true;
          upgrade = true;
          cleanup = "zap";
        };
      };

      networking = {
        computerName = host.hostName;
        localHostName = host.hostName;
      };
    };
}
