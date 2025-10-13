# This is a home manager config
{ lib, pkgs, pkgs-unstable, ... }:

{
  home.packages = [
    # The quickshell config depends on hyprland-info for workspace and icon information
    # for the workspace list and current window components.
    (pkgs.callPackage ./utils/hyprland-info {})

    # The quickshell config depends on nm-status to resolve live NetworkManager
    # status info for the tooltip in particular
    (pkgs.callPackage ./utils/nm-status {})
  ];

  wayland.windowManager.hyprland.settings = {
    exec-once = [
      # Needed for the Network status icon. Read `config/blocks/Network.qml`
      "${lib.getExe pkgs.networkmanagerapplet} --indicator"

      "${lib.getExe pkgs-unstable.quickshell} --path ${./config}"
    ];
  };
}
