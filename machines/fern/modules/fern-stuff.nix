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
    ];
  };

  nixos = { ... }: {
    virtualisation.docker.enable = true;

    users.users.andrew.extraGroups = [ "docker" ];
  };
}
