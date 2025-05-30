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

  services.asusd.enable = true;

  services.tlp.enable = true;

  # Nvidia related shenans
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = true;
    nvidiaSettings = true;
  };
  
  # Make GDM scale properly on the built in screen
  programs.dconf.profiles.gdm.databases = [{
    settings."org/gnome/desktop/interface".scaling-factor = lib.gvariant.mkUint32 2;
  }];

}

