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

      splitDnsDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "serie" ];
        description = ''
          Tailscale split-DNS domains to resolve via MagicDNS on Darwin.

          The open-source tailscaled we run on macOS (see below) lacks the
          Network Extension entitlement the GUI app uses, so it never installs
          split-DNS routes (e.g. "serie" -> a node running its own DNS) into the
          system resolver. Each domain listed here gets an /etc/resolver/<domain>
          file pointing at MagicDNS (100.100.100.100), mirroring how the
          ts.net suffix already works, so names like immich.serie resolve.
        '';
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

  # On Darwin we run nix's open-source tailscaled rather than the macsys GUI
  # app, because the sandboxed GUI build refuses to run the Tailscale SSH
  # server. This is incompatible with installing the "tailscale-app" homebrew
  # cask alongside — the cask must be removed so the nix daemon owns the tun.
  darwin = { lib, pkgs, universalConfig ? {}, ... }:
    let
      enableSSH = universalConfig.tailscale.ssh or false;
      sshFlag = if enableSSH then "true" else "false";
      splitDnsDomains = universalConfig.tailscale.splitDnsDomains or [ ];
    in
    {
      services.tailscale.enable = true;

      # tailscaled on macOS doesn't install split-DNS routes into the system
      # resolver, so point each configured domain at MagicDNS ourselves.
      environment.etc = lib.listToAttrs (map (domain: {
        name = "resolver/${domain}";
        value.text = "nameserver 100.100.100.100\n";
      }) splitDnsDomains);

      system.activationScripts.postActivation.text = lib.mkAfter ''
        ${pkgs.tailscale}/bin/tailscale set --ssh=${sshFlag} 2>/dev/null \
          || echo "note: tailscale set --ssh=${sshFlag} skipped (daemon not running or not signed in; run 'tailscale up' once)"
      '';
    };
}
