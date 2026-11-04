# This is a home manager config
{ lib, pkgs, pkgs-unstable, inputs, universalConfig ? {}, ... }:

let
  isVmMode = universalConfig.andrew-shell.vm-mode or false;
  newBar = universalConfig.andrew-shell.experimentalNewBar or false;

  hyprland-info = pkgs.callPackage ./utils/hyprland-info { naersk-input = inputs.naersk; };
  calendar-status = pkgs.callPackage ./utils/calendar-status { naersk-input = inputs.naersk; };

  # The Rune bar (../rune-bar), with the programs it runs.
  andrew-bar = pkgs.callPackage ../rune-bar/package.nix {
    extraPath = [
      hyprland-info
      calendar-status
      pkgs.networkmanager        # nmcli
      pkgs.networkmanagerapplet  # nm-connection-editor
      pkgs.wireplumber           # wpctl
      pkgs.pipewire              # pw-dump
      pkgs.upower
      pkgs.pavucontrol
      pkgs.fontconfig.bin        # fc-match
      pkgs.xdg-utils
    ];
  };
in
{
  home.packages = [
    # The quickshell config depends on hyprland-info for workspace and icon information
    # for the workspace list and current window components.
    hyprland-info
  ] ++ lib.optionals (!isVmMode && !newBar) [
    # The quickshell config depends on nm-status to resolve live NetworkManager
    # status info for the tooltip in particular (not needed in VM mode)
    (pkgs.callPackage ./utils/nm-status { naersk-input = inputs.naersk; })

    # calendar-status reads Thunderbird's CalDAV cache to power the calendar
    # countdown block (not needed in VM mode)
    calendar-status
  ] ++ lib.optional newBar andrew-bar;

  wayland.windowManager.hyprland.settings = {
    exec-once = (if newBar then [
      # The bar, and the notification daemon.
      (lib.getExe andrew-bar)
    ] else [
      "${lib.getExe pkgs-unstable.quickshell} --path ${./config}"
      "${lib.getExe pkgs.swaynotificationcenter}"
    ]) ++ lib.optional (!isVmMode) (
      # nm-applet is NetworkManager's secret agent (the Wi-Fi password dialog) for both bars,
      # and Quickshell's Network status icon. Read `config/blocks/Network.qml`
      "${lib.getExe pkgs.networkmanagerapplet} --indicator"
    );
  };
}
