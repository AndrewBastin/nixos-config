{
  home = { pkgs, pkgs-unstable, ... }: {
    home.packages = with pkgs; [
      nh
      dino
      firefox
      pkgs-unstable.thunderbird
      pkgs-unstable.slack
      pkgs-unstable.cider-2
      pkgs-unstable.todoist-electron
      pkgs-unstable.obsidian
      pkgs-unstable.fractal
      pkgs-unstable.vlc
    ];
  };

  nixos = { ... }: {
    virtualisation.docker.enable = true;

    users.users.andrew.extraGroups = [ "docker" "libvirtd" ];

    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
  };
}
