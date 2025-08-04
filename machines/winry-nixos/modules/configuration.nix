{ config, pkgs, ... }:

{
    imports =
      [ # Include the results of the hardware scan.
        ./hardware-configuration.nix
      ];


    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Bootloader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Use latest kernel.
    boot.kernelPackages = pkgs.linuxPackages_latest;

    networking.hostName = "winry-nixos"; # Define your hostname.

    networking.networkmanager.enable = true;

    boot.binfmt.emulatedSystems = ["x86_64-linux"];
    nixpkgs.config.allowUnsupportedSystem = true;

    # Set your time zone.
    time.timeZone = "Asia/Kolkata";

    # Select internationalisation properties.
    # i18n.defaultLocale = "en_US.UTF-8";
    #
    # i18n.extraLocaleSettings = {
    #   LC_ADDRESS = "en_US.UTF-8";
    #   LC_IDENTIFICATION = "en_US.UTF-8";
    #   LC_MEASUREMENT = "en_US.UTF-8";
    #   LC_MONETARY = "en_US.UTF-8";
    #   LC_NAME = "en_US.UTF-8";
    #   LC_NUMERIC = "en_US.UTF-8";
    #   LC_PAPER = "en_US.UTF-8";
    #   LC_TELEPHONE = "en_US.UTF-8";
    #   LC_TIME = "en_US.UTF-8";
    #   LC_CTYPE = "en_US.UTF-8";
    # };


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
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;
    };

    # Enable touchpad support (enabled default in most desktopManager).
    # services.xserver.libinput.enable = true;

    # Define a user account. Don't forget to set a password with 'passwd'.
    users.users.andrew = {
      isNormalUser = true;
      description = "Andrew";
      group = "andrew";
      extraGroups = [ "networkmanager" "wheel" "video" "input" ];
      packages = [
      #  thunderbird
      ];
    };

    # Create the andrew group
    users.groups.andrew = {};

    # Auto-login is handled by the dwm module

    # Install firefox.
    programs.firefox.enable = true;

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;


    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
      xfce.thunar
      nh
      ghostty
      gtkmm3
      st
      dconf
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

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    # programs.gnupg.agent = {
    #   enable = true;
    #   enableSSHSupport = true;
    # };

    # List services that you want to enable:

    # Enable the OpenSSH daemon.
    # services.openssh.enable = true;

    # Open ports in the firewall.
    # networking.firewall.allowedTCPPorts = [ ... ];
    # networking.firewall.allowedUDPPorts = [ ... ];
    # Or disable the firewall altogether.
    # networking.firewall.enable = false;

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "25.05"; # Did you read the comment?
}

