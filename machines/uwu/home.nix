{ pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./hm-modules/aerospace
    (import ./hm-modules/kitty { fontSize = 14; })
  ];

  home.packages = with pkgs; [
    nh
    pkgs-unstable.numi
  ];

  home.stateVersion = "24.11";
}
