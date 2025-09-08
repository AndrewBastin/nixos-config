# This is a home manager config
{ lib, pkgs, pkgs-unstable, ... }:

{

  wayland.windowManager.hyprland.settings = {
    exec-once = [
      # Needed for the Network status icon. Read `config/blocks/Network.qml`
      "${lib.getExe pkgs.networkmanagerapplet} --indicator"

      "${lib.getExe pkgs-unstable.quickshell} --path ${./config}"
    ];
  };
}
