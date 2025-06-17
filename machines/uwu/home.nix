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
  ];

  home.stateVersion = "24.11";
}
