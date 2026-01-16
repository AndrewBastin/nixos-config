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

    # As part of the Jujutsu experiment, should graduate into
    # dev-essentials if deemed useful
    programs.jujutsu = {
      enable = true;
      package = pkgs-unstable.jujutsu;
      settings = {
        user = {
          email = "andrewbastin.k@gmail.com";
          name = "Andrew Bastin";
        };

        ui.default-command = "log";
      };
    };
  };

  nixos = { ... }: {
    virtualisation.docker.enable = true;

    users.users.andrew.extraGroups = [ "docker" "libvirtd" ];

    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
  };
}
