{ config, pkgs, ... }:

{
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Bootloader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Use latest kernel.
    boot.kernelPackages = pkgs.linuxPackages_latest;

    networking.hostName = "winry-nixos";

    networking.networkmanager.enable = true;

    boot.binfmt.emulatedSystems = ["x86_64-linux"];
    nixpkgs.config.allowUnsupportedSystem = true;

    # Set your time zone.
    time.timeZone = "Asia/Kolkata";

    # Enable CUPS to print documents.
    services.printing.enable = true;

    # Enable sound with pipewire.
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    users.users.andrew = {
      isNormalUser = true;
      description = "Andrew";
      extraGroups = [ "networkmanager" "wheel" ];
      packages = [];
    };

    # Install firefox.
    programs.firefox.enable = true;

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
      xfce.thunar
      nh
      ghostty
      gtkmm3
      st
      dconf
      foot
    ];

    virtualisation.vmware.guest.enable = true;

    fileSystems."/mac" = {
      fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
      device = ".host:/";
      options = [
        "umask=22"
        "uid=1000"
        "gid=1000"
        "allow_other"
        "auto_unmount"
        "defaults"
      ];
    };
}

