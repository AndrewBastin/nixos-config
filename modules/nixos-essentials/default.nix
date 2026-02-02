# Essential configuration that is present in pretty much
# all my NixOS systems
{
  home = { pkgs, ... }: {
    # Comma and nix-index is used to index nixpkgs
    home.packages = with pkgs; [
      nix-index
      comma
    ];
  };

  nixos = { pkgs, inputs, ... }: {
    nix.settings.experimental-features = ["nix-command" "flakes"];

    # Register all flake inputs in the nix registry
    # Enables: nix run nixpkgs#hello, nix run nixpkgs-unstable#firefox, etc.
    nix.registry = builtins.mapAttrs (_name: flake: { inherit flake; }) inputs;

    nixpkgs.config.allowUnfree = true;
    
    # Use `nh` for NixOS scripts
    # Also set up store cleanup jobs to run every week
    # The store cleanup will keep the last 5 generations and
    # generations made since past 7 days
    programs.nh = {
      enable = true;

      clean = {
        enable = true;
        dates = "weekly";
        extraArgs = "--keep 5 --keep-since 7d";
      };
    };

    # Firmware Updater
    services.fwupd.enable = true;
  };
}
