# Tailscale Module
# Enables Tailscale VPN with optional Tailscale SSH support.
{
  options = { lib, ... }: {
    tailscale = {
      ssh = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Tailscale SSH";
      };
    };
  };

  nixos = { lib, universalConfig ? {}, ... }:
    let
      enableSSH = universalConfig.tailscale.ssh or false;
    in
    {
      services.tailscale.enable = true;
      services.tailscale.extraUpFlags = lib.optionals enableSSH [ "--ssh" ];

      networking.firewall.trustedInterfaces = lib.optionals enableSSH [ "tailscale0" ];

      # Don't block boot for waiting on networking
      systemd.network.wait-online.enable = false;
      boot.initrd.systemd.network.wait-online.enable = false;
    };

  # TODO: Tailscale SSH on Darwin
  darwin = { ... }: {
    services.tailscale.enable = true;
  };
}
