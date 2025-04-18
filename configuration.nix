# This is configuration that is common to all machines that are defined.
# System specific machines can be defined on that machine level
# See ./machines/default.nix for reference

{ pkgs, hostname, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nix.extraOptions = ''
    trusted-users = root andrew
    extra-substituters = https://nixpkgs-python.cachix.org https://devenv.cachix.org
    extra-trusted-public-keys = nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU= devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=
  '';

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = hostname;

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Kolkata";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_IN";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_IN";
    LC_IDENTIFICATION = "en_IN";
    LC_MEASUREMENT = "en_IN";
    LC_MONETARY = "en_IN";
    LC_NAME = "en_IN";
    LC_NUMERIC = "en_IN";
    LC_PAPER = "en_IN";
    LC_TELEPHONE = "en_IN";
    LC_TIME = "en_IN";
  };

  services.xserver.displayManager.gdm.enable = true;

  services.printing.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # nh - Nix Helper
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
  };

  users.users.andrew = {
    isNormalUser = true;
    description = "Andrew Bastin";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = [ ]; # NOTE: Managed separately in home manager (checkout home.nix)
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    clang
    curl
    wget
    htop
    bat
  ];

  # Fix for Chromium and Electron to work without Xwayland 
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  environment.variables.EDITOR = "nvim";

  services.gnome.gnome-keyring.enable = true;

  services.flatpak.enable = true;

  # Git Config
  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    config.credential.helper = "libsecret";
    config.init.defaultBranch = "main";
  };

  programs.appimage = {
    enable = true;

    # Registers binfmt to set the interpreter for Appimage files as appimage-run
    binfmt = true;
  };

  virtualisation.docker.enable = true;

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "NerdFontsSymbolsOnly" "JetBrainsMono" ]; })
  ];

  programs.hyprland.enable = true;

  # Hyprlock
  programs.hyprlock.enable = true;
  security.pam.services.hyprlock = {};

  # NPM
  environment.etc.npmrc.source = ./config/npm/.npmrc;

  # Polkit
  security.polkit.enable = true;

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
  };


  system.stateVersion = "24.11";

}
