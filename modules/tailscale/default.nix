# Tailscale Module
# Enables Tailscale VPN and trusts the tailscale0 interface in the firewall.
{
  options = { lib, ... }: {
    tailscale.enableSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SSH server accessible via Tailscale";
    };
  };

  nixos = { universalConfig ? {}, lib, ... }: {
    services.tailscale.enable = true;

    # Enable SSH server if configured
    services.openssh = lib.mkIf universalConfig.tailscale.enableSSH {
      enable = true;
      settings = {
        # NOTE: This is super dumb!!!!!!!! Switch to SSH keys when secret management is setup!
        # For now, the firewall only trusts tailscale completely, but this is still not super good!
        PasswordAuthentication = true;
        KbdInteractiveAuthentication = true;
      };
    };

    networking.firewall = {
      # Trust Tailscale interface completely (allows SSH and all other traffic)
      trustedInterfaces = [ "tailscale0" ];

      # Optionally: If you want SSH accessible from other interfaces too, uncomment:
      # allowedTCPPorts = [ 22 ];
    };

    # Don't block boot for waiting on networking
    systemd.network.wait-online.enable = false;
    boot.initrd.systemd.network.wait-online.enable = false;
  };
}
