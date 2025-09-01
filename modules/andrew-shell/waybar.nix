# NOTE: This is a home manager module
{ lib, pkgs, ... }:

{
  programs.waybar = {
    enable = true;
    style = /* css */ ''
      /* -----------------------------------------------------
      *                      Config
      * ----------------------------------------------------- */

      @define-color bg #161616;
      @define-color bg2 #262626;
      @define-color bg3 #393939;
      @define-color bg4 #525252;
      @define-color fg #D8D8D8;
      @define-color fg2 #c6c6c6;
      @define-color red #DA1E28;
      @define-color blue #78A9FF;
      @define-color purple #BE95FF;

      * {
        font-family:
          JetBrains Mono,
          Symbols Nerd Font Mono,
          sans-serif;
        font-size: 14px;
        border-radius: 0;
        border: none;
        box-shadow: none;
        transition: none;
      }

      /* -----------------------------------------------------
      *                      Window
      * ----------------------------------------------------- */

      window#waybar {
        color: @fg;
        background-color: @bg;
      }

      /* -----------------------------------------------------
      *                      Tooltip
      * ----------------------------------------------------- */

      tooltip {
        background: @bg;
        border: solid 1px @bg3;
      }

      tooltip label {
        color: @fg;
      }

      button:hover {
        background: @bg2;
      }

      /* -----------------------------------------------------
      *                      Modules
      * ----------------------------------------------------- */

      #workspaces button {
        color: @fg;
      }

      #battery,
      #pulseaudio,
      #custom-mic,
      #cpu,
      #memory,
      #idle_inhibitor,
      #tray,
      #clock,
      #custom-notification,
      #network {
        color: @fg;
        padding: 0 8px;
      }

      #tray menu {
        background-color: @bg;
        border: solid 1px @bg3;
      }
      #custom-weather {
        color: @fg2;
        padding-left: 10px;
      }
      #custom-sep,
      #custom-markl,
      #custom-markr {
        color: @bg4;
        padding: 0 4px;
      }
      #mpris {
        color: @fg2;
        padding: 0 10px;
      }

      #custom-clock,
      #clock {
        color: @fg;
        padding: 0 4px;
      }

      #custom-power {
        color: @fg;
        padding: 0 10px;
      }
    '';

    settings = {
      mainBar = {
        layer = "bottom";
        height = 32;
        position = "top";

        modules-left = ["hyprland/workspaces" "hyprland/window"];

        modules-right = [
          "group/sys"
          "pulseaudio"
          "network"
          "battery"
          "custom/notification"
          "clock"
        ];

        tray = {
          icon-size = 16;
          spacing = 10;
        };

        "group/sys" = {
          orientation = "horizontal";

          drawer = {
            transition-left-to-right = true;
            click-to-reveal = true;
            transition-duration = 500;
          };

          modules = ["custom/markl" "idle_inhibitor" "tray"];
        };

        "hyprland/workspaces" = {
          format = "{icon}";
          active-only = true;
        };

        "hyprland/window" = {
          format = "{}";
          icon = true;
          icon-size = 18;
        };

        battery = {
          bat = "BAT0";
          interval = 60;
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon}";
          format-icons = ["󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
          tooltip-format = "{capacity}% {timeTo}";
          max-length = 25;
        };

        network = {
          format-wifi = "{icon}";
          format-ethernet = "";
          tooltip-format-wifi = "{essid} {signalStrength}%";
          tooltip-format-disconnected = "No connection";
          format-linked = "{ifname} (No IP) ?";
          format-disconnected = "󰅛";
          max-length = 30;
          format-icons = ["󰣾" "󰣴" "󰣶" "󰣸" "󰣺"];
          on-click = "${lib.getExe pkgs.kitty} -e ${pkgs.networkmanager}/bin/nmtui";
        };

        pulseaudio = {
          format = "{icon}";
          format-bluetooth = "{icon}";
          format-muted = "";
          format-icons = {
              # "alsa_output.pci-0000_00_1f.3.analog-stereo": "",
              # "alsa_output.pci-0000_00_1f.3.analog-stereo-muted": "",
              headphone = "";
              hands-free = "";
              headset = "";
              phone = "";
              phone-muted = "";
              portable = "";
              car = "";
              default = ["" ""];
          };
          scroll-step = 1;
          on-click = lib.getExe pkgs.pavucontrol;
          # ignored-sinks = ["Easy Effects Sink"];
        };

        clock = {
          format = "{:%a %b %d %OI:%M %p}";
          tooltip = false;
        };

        "custom/notification" = let
          swaync-client = "${pkgs.swaynotificationcenter}/bin/swaync-client";
        in
          {
            tooltip = true;
            tooltip-format = "{} notifications";
            format = "{icon}";
            format-icons = {
              notification = "󱅫";
              none = "";

              # I don't want to know if I have notifications when I am in DnD
              dnd-notification = "󰂛";
              dnd-none = "󰂛";

              # When notifications are inhibited, I want to know if there is a notification, but
              # don't want it to take my attention. I also want to know if there is inhibition
              inhibited-notification = "󱅫";
              inhibited-none = "󰂠";

              # I don't want to know if I have notifications when I am in DnD
              dnd-inhibited-notification = "󰂛";
              dnd-inhibited-none = "󰂛";
            };
            return-type = "json";
            # exec-if = "which swaync-client",
            exec = "${swaync-client} -swb";
            on-click = "${swaync-client} -t -sw";
            on-click-right = "${swaync-client} -d -sw";
            escape = true;
          };

        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰒳";
            deactivated = "󰒲";
          };
        };

        "custom/markr" = {
          interval = "once";
          format = "";
          tooltip = false;
        };

        "custom/markl" = {
          interval = "once";
          format = "";
          tooltip = false;
        };
      };
    };
  };
}

