# Quick menu scripts to do different operations, all of them use the same themed runner
# Powered by bemenu
{
  writeShellScript,

  lib,

  bemenu,
  bluez,
  libnotify,
  hyprlock,

  fontFamily ? "BerkeleyMono Nerd Font Mono"
}:

let
  bemenu_runner = writeShellScript "andrew-bemenu" /* sh */ ''
    BEMENU_ARGS=(
      -i        # Filter items case-insensitively
      -H28      # Line-height
      -P '*'    # Prefix
      --cw '2'  # Width of the cursor
      --ch '18' # Height of the cursor
      --hp '8'  # Horizontal padding for the entries in single line mode
      --fn '${fontFamily} 16px'
      --tb '#161616' --tf '#be95ff'
      --fb '#161616' --ff '#ffffff'
      --cb '#161616' --cf '#525252'
      --nb '#161616' --nf '#e0e0e0'
      --ab '#161616' --af '#e0e0e0'
      --hb '#161616' --hf '#be95ff'
      --bdr '#262626' --cf '#323232'
      --single-instance
      "$@")

    ${lib.getExe bemenu} "''${BEMENU_ARGS[@]}"
  '';
in
  {
    bluetooth = let
      bluetoothctl = "${bluez}/bin/bluetoothctl";
      notify-send = lib.getExe libnotify;
    in 
    writeShellScript "andrew-bemenu-bluetooth" /* sh */ ''
      set -euo pipefail

      # Get list of paired devices with connection status
      # Store device info with MAC addresses for reliable lookup
      declare -A DEVICE_MACS
      declare -A DEVICE_STATUS
      DEVICES=""

      while IFS= read -r line; do
        MAC=$(echo "$line" | cut -d' ' -f2)
        NAME=$(echo "$line" | cut -d' ' -f3-)
        
        # Store MAC address for this device name
        DEVICE_MACS["$NAME"]="$MAC"
        
        # Check if device is connected and get battery info
        DEVICE_INFO=$(${bluetoothctl} info "$MAC")
        if echo "$DEVICE_INFO" | grep -q "Connected: yes"; then
          # Try to get battery percentage
          BATTERY=""
          if echo "$DEVICE_INFO" | grep -q "Battery Percentage:"; then
            BATTERY_LEVEL=$(echo "$DEVICE_INFO" | grep "Battery Percentage:" | sed 's/.*Battery Percentage: 0x\(..\).*/\1/')
            # Convert hex to decimal
            BATTERY_PCT=$((16#$BATTERY_LEVEL))
            
            # Select battery icon based on percentage (matching waybar icons)
            if [ $BATTERY_PCT -le 5 ]; then
              BATTERY_ICON="󰂎"
            elif [ $BATTERY_PCT -le 15 ]; then
              BATTERY_ICON="󰁺"
            elif [ $BATTERY_PCT -le 25 ]; then
              BATTERY_ICON="󰁻"
            elif [ $BATTERY_PCT -le 35 ]; then
              BATTERY_ICON="󰁼"
            elif [ $BATTERY_PCT -le 45 ]; then
              BATTERY_ICON="󰁽"
            elif [ $BATTERY_PCT -le 55 ]; then
              BATTERY_ICON="󰁾"
            elif [ $BATTERY_PCT -le 65 ]; then
              BATTERY_ICON="󰁿"
            elif [ $BATTERY_PCT -le 75 ]; then
              BATTERY_ICON="󰂀"
            elif [ $BATTERY_PCT -le 85 ]; then
              BATTERY_ICON="󰂁"
            elif [ $BATTERY_PCT -le 95 ]; then
              BATTERY_ICON="󰂂"
            else
              BATTERY_ICON="󰁹"
            fi
            
            BATTERY=" ''${BATTERY_ICON} ''${BATTERY_PCT}%"
          fi
          DEVICES="''${DEVICES}''${NAME}''${BATTERY} [CONNECTED]\n"
          DEVICE_STATUS["$NAME"]="connected"
        else
          DEVICES="''${DEVICES}''${NAME}\n"
          DEVICE_STATUS["$NAME"]="disconnected"
        fi
      done < <(${bluetoothctl} devices)

      # If no devices found, exit
      if [ -z "$DEVICES" ]; then
        echo "No paired devices found" | ${bemenu_runner} -n -B1 -l1 -p "Bluetooth"
        exit 1
      fi

      # Show device selection menu
      SELECTED=$(echo -e "$DEVICES" | sed '/^$/d' | ${bemenu_runner} -n -B1 -l10 -p "Connect to:")

      # If selection was cancelled, exit
      if [ -z "$SELECTED" ]; then
        exit 0
      fi

      # Remove display suffixes (battery icon, percentage and connection status) to get actual device name
      DEVICE_NAME=$(echo "$SELECTED" | sed -E 's/ [󰂎󰁺󰁻󰁼󰁽󰁾󰁿󰂀󰂁󰂂󰁹] [0-9]+%| \[CONNECTED\]//g')

      # Get MAC address from our stored mapping
      MAC="''${DEVICE_MACS[$DEVICE_NAME]}"

      # Function to get battery info for a device
      get_battery_info() {
        local mac="$1"
        local device_info=$(${bluetoothctl} info "$mac")
        
        if echo "$device_info" | grep -q "Battery Percentage:"; then
          local battery_level=$(echo "$device_info" | grep "Battery Percentage:" | sed 's/.*Battery Percentage: 0x\(..\).*/\1/')
          local battery_pct=$((16#$battery_level))
          
          # Select battery icon based on percentage
          local battery_icon
          if [ $battery_pct -le 5 ]; then
            battery_icon="󰂎"
          elif [ $battery_pct -le 15 ]; then
            battery_icon="󰁺"
          elif [ $battery_pct -le 25 ]; then
            battery_icon="󰁻"
          elif [ $battery_pct -le 35 ]; then
            battery_icon="󰁼"
          elif [ $battery_pct -le 45 ]; then
            battery_icon="󰁽"
          elif [ $battery_pct -le 55 ]; then
            battery_icon="󰁾"
          elif [ $battery_pct -le 65 ]; then
            battery_icon="󰁿"
          elif [ $battery_pct -le 75 ]; then
            battery_icon="󰂀"
          elif [ $battery_pct -le 85 ]; then
            battery_icon="󰂁"
          elif [ $battery_pct -le 95 ]; then
            battery_icon="󰂂"
          else
            battery_icon="󰁹"
          fi
          
          echo " ''${battery_icon} ''${battery_pct}%"
        else
          echo ""
        fi
      }

      # Connect or disconnect based on current status
      if [ "''${DEVICE_STATUS[$DEVICE_NAME]}" = "connected" ]; then
        if ${bluetoothctl} disconnect "$MAC"; then
          ${notify-send} "Bluetooth" "Disconnected from $DEVICE_NAME"
        else
          ${notify-send} "Bluetooth" "Failed to disconnect from $DEVICE_NAME" -u critical
        fi
      else
        if ${bluetoothctl} connect "$MAC"; then
          # Get battery info after connection
          sleep 1  # Give device time to report battery status
          BATTERY_INFO=$(get_battery_info "$MAC")
          ${notify-send} "Bluetooth" "Connected to $DEVICE_NAME$BATTERY_INFO"
        else
          ${notify-send} "Bluetooth" "Failed to connect to $DEVICE_NAME" -u critical
        fi
      fi
    '';

    power = writeShellScript "andrew-bemenu-power" /* sh */ ''
      CONFIRM="${bemenu_runner} -n -W 0.10 -B1 --bdr #DA1E28 -l2 -p Sure?"

      case $(printf "%s\n" "Lock" "Logout" "Suspend" "Hibernate" "Reboot" "Shutdown" | ${bemenu_runner} -n -B1 -l6 -p Quit?) in
      "Shutdown")
        confirm=$(echo -e "Yes\nNo" | $CONFIRM)
        if [[ "$confirm" == "Yes" ]]; then
          poweroff
        fi
        ;;
      "Reboot")
        confirm=$(echo -e "Yes\nNo" | $CONFIRM)
        if [[ "$confirm" == "Yes" ]]; then
          reboot
        fi
        ;;
      "Suspend")
        loginctl suspend
        ;;
      "Hibernate")
        systemctl hibernate
        ;;
      "Lock")
        ${lib.getExe hyprlock}
        ;;
      "Logout")
        loginctl terminate-session "''${XDG_SESSION_ID-}"
        ;;
      esac
    '';
  }
