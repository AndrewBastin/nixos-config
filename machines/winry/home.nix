{ pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./hm-modules/aerospace
    (import ./hm-modules/kitty { fontSize = 14; })
  ];

  home.packages = with pkgs; [
    nh
    nix-output-monitor
    pkgs-unstable.numi
    tig
    gh
    nodejs_20
  ];

  programs.git = {
    enable = true;
    userName = "Andrew Bastin";
    userEmail = "andrewbastin.k@gmail.com";
  };

  home.stateVersion = "24.11";
}
