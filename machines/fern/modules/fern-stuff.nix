{
  home = { pkgs, pkgs-unstable, ... }: {
    home.packages = with pkgs; [
      nh
      firefox
      pkgs-unstable.thunderbird
      pkgs-unstable.slack
      pkgs-unstable.cider-2
      pkgs-unstable.obsidian
      pkgs-unstable.vlc
      pkgs-unstable.signal-desktop
    ];
  };

  nixos = { pkgs, ... }: {
    virtualisation.docker.enable = true;

    # Expose the NVIDIA GPU to Docker containers via CDI (for CUDA workloads).
    hardware.nvidia-container-toolkit.enable = true;

    users.users.andrew.extraGroups = [ "docker" "libvirtd" "dialout" ];

    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
    
    programs.steam.enable = true;

    # Allow OpenVPN Plugins
    networking.networkmanager.plugins = with pkgs; [
      networkmanager-openvpn
    ];
  };
}
