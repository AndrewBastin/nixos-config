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
    package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
      # A temporary patch until 570 drivers hit NixOS repos
      # Ref: https://github.com/NixOS/nixpkgs/issues/375730#issuecomment-2625234288
      version = "570.133.07";
      sha256_64bit = "sha256-LUPmTFgb5e9VTemIixqpADfvbUX1QoTT2dztwI3E3CY=";
      sha256_aarch64 = "sha256-yTovUno/1TkakemRlNpNB91U+V04ACTMwPEhDok7jI0=";
      openSha256 = "sha256-9l8N83Spj0MccA8+8R1uqiXBS0Ag4JrLPjrU3TaXHnM=";
      settingsSha256 = "sha256-XMk+FvTlGpMquM8aE8kgYK2PIEszUZD2+Zmj2OpYrzU=";
      usePersistenced = false;
    };
  };
  
  # Make GDM scale properly on the built in screen
  programs.dconf.profiles.gdm.databases = [{
    settings."org/gnome/desktop/interface".scaling-factor = lib.gvariant.mkUint32 2;
  }];

}

