# Universal sub-module that, when enabled, packages and runs librepods
# (kavishdevar/librepods linux/rust branch) as a Hyprland session process,
# and applies the system-level prerequisites for full feature support:
#   - BlueZ DeviceID = bluetooth:004C:0000:0000 (advertises this host as
#     Apple-class so AirPods unlock feature flags + multi-device handoff)
#   - WirePlumber `bluez5.dummy-avrcp-player = true` (so AirPods tap gestures
#     emit MPRIS play/pause/skip events)
{
  options = { lib, ... }: {
    andrew-shell.librepods = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          If enabled, runs librepods as a Hyprland session process and applies
          the BlueZ DeviceID + WirePlumber AVRCP tweaks needed for full AirPods
          feature support, including multi-device handoff with Apple devices.
        '';
      };
    };
  };

  nixos = { config, pkgs, lib, universalConfig ? {}, ... }:
    let
      cfg = universalConfig.andrew-shell.librepods or {};
    in
      lib.mkIf (cfg.enable or false) {
        # Advertise this host as Apple-class in the Bluetooth Device ID
        # Profile. Without this, AirPods refuse the 0x4D feature-flags
        # opcode and will not relay SmartRouting packets to other peers,
        # which means handoff and hearing-aid silently no-op.
        hardware.bluetooth = {
          enable = lib.mkDefault true;
          settings.General.DeviceID = lib.mkDefault "bluetooth:004C:0000:0000";
        };

        # AirPods send AVRCP commands for tap/double-tap/triple-tap. Without
        # this, those events have no MPRIS player to land on and play/pause
        # silently fails. Only meaningful when PipeWire is the audio stack.
        services.pipewire.wireplumber.extraConfig = lib.mkIf config.services.pipewire.enable {
          bluetoothEnhancements = {
            "monitor.bluez.properties" = {
              "bluez5.dummy-avrcp-player" = true;
            };
          };
        };
      };

  home = { pkgs, lib, inputs, universalConfig ? {}, ... }:
    let
      cfg = universalConfig.andrew-shell.librepods or {};
      enabled = cfg.enable or false;
      librepodsPkg = pkgs.callPackage ./package.nix {
        naersk-input = inputs.naersk;
      };
    in
      lib.mkIf enabled {
        # `librepods-ctl` lands on PATH via this. The bluetooth bemenu in
        # ../quickmenu.nix detects its presence and routes to an AirPods
        # sub-menu when the selected device matches librepods's view.
        home.packages = [ librepodsPkg ];

        wayland.windowManager.hyprland.settings.exec-once = [
          "${librepodsPkg}/bin/librepods"
        ];
      };
}
