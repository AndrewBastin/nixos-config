# Tailscale Module
# Enables Tailscale VPN and trusts the tailscale0 interface in the firewall.
{
  options = { ... }: {
  };

  nixos = { ... }: {
    services.tailscale.enable = true;

    # Don't block boot for waiting on networking
    systemd.network.wait-online.enable = false;
    boot.initrd.systemd.network.wait-online.enable = false;
  };

  darwin = { ... }: {
    services.tailscale.enable = true;
  };
}
