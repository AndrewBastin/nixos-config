# This is a home manager config
{ lib, pkgs, pkgs-unstable, inputs, universalConfig ? {}, ... }:

let
  isVmMode = universalConfig.andrew-shell.vm-mode or false;
in
{
  home.packages = [
    # The quickshell config depends on hyprland-info for workspace and icon information
    # for the workspace list and current window components.
    (pkgs.callPackage ./utils/hyprland-info { naersk-input = inputs.naersk; })
  ] ++ lib.optional (!isVmMode) (
    # The quickshell config depends on nm-status to resolve live NetworkManager
    # status info for the tooltip in particular (not needed in VM mode)
    pkgs.callPackage ./utils/nm-status { naersk-input = inputs.naersk; }
  );

  wayland.windowManager.hyprland.settings = {
    exec-once = [
      "${lib.getExe pkgs-unstable.quickshell} --path ${./config}"
    ] ++ lib.optional (!isVmMode) (
      # Needed for the Network status icon. Read `config/blocks/Network.qml`
      "${lib.getExe pkgs.networkmanagerapplet} --indicator"
    );
  };
}
