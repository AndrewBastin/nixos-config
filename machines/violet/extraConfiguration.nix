{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    asusctl
    supergfxctl
  ];

  # https://mtoohey.com/articles/nixos-on-g14/
  services.supergfxd = {
    enable = true;
    settings = {
      mode = "Hybrid";
    };
  };

  services.power-profiles-daemon.enable = true;

  systemd.services.power-profiles-daemon = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
  };

  services.asusd.enable = true;

  # Nvidia related shenans
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
      # A temporary patch until 570 drivers hit NixOS repos
      # Ref: https://github.com/NixOS/nixpkgs/issues/375730#issuecomment-2625234288
      version = "570.124.04";
      sha256_64bit = "sha256-G3hqS3Ei18QhbFiuQAdoik93jBlsFI2RkWOBXuENU8Q=";
      openSha256 = "sha256-DuVNA63+pJ8IB7Tw2gM4HbwlOh1bcDg2AN2mbEU9VPE=";
      settingsSha256 = "sha256-LNL0J/sYHD8vagkV1w8tb52gMtzj/F0QmJTV1cMaso8=";
      usePersistenced = false;
    };
  };
  
  # Make GDM scale properly on the built in screen
  programs.dconf.profiles.gdm.databases = [{
    settings."org/gnome/desktop/interface".scaling-factor = lib.gvariant.mkUint32 2;
  }];

}

