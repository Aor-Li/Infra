# 关掉它你会失去：NetworkManager——Wi-Fi / 有线的联网与自动重连（nmcli / nmtui）。
{ lib, ... }:
{
  den.aspects.network.core =
    { host, ... }:
    {
      # WSL 的网络由宿主 Windows 提供，不需要也不应该跑 NetworkManager。
      nixos = lib.mkIf (host.virt != "wsl") {
        networking.networkmanager.enable = lib.mkDefault true;
      };
    };
}
