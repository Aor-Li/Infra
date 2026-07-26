{ ... }:
{
  den.aspects.network.tailscale.nixos =
    { ... }:
    {
      # TODO: 搭好 secrets（sops）后再开启：
      #   - 用 authKeyFile 配 pre-auth key 免交互加入 tailnet；
      #   - 届时 enable = true（或按角色门控），并考虑补 darwin 分支让 Magatsumi 也入网。
      # 在此之前保持关闭；需要时也可先手动 `tailscale up` 交互授权。
      services.tailscale.enable = false;
    };
}
