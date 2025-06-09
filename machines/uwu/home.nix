{ pkgs, ... }:

{
  imports = [
    ./hm-modules/aerospace
    (import ./hm-modules/kitty { fontSize = 14; })
  ];

  home.packages = with pkgs; [
    nh
  ];

  home.stateVersion = "24.11";
}
