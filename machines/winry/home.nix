{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nh
    nix-output-monitor
    aria2
  ];
}
