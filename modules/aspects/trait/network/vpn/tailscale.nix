# 关掉它你会失去：通过 Tailscale 私有网络访问其他设备的能力。
{
  den.aspects.network.vpn.tailscale = {
    # 系统级隧道需要在没有用户会话时仍然工作；首次登录在实机完成。
    nixos.services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    # 使用官方 Standalone GUI，与 macOS 的 VPN / 网络扩展集成。
    # 不同时启动 nix-darwin 的 tailscaled，避免两个客户端争用网络。
    darwin.homebrew.casks = [ "tailscale-app" ];
  };
}
