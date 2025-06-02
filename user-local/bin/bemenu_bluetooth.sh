#!/usr/bin/env bash
# Bluetooth device selector using bemenu
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
  DEVICE_INFO=$(bluetoothctl info "$MAC")
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
      
      BATTERY=" ${BATTERY_ICON} ${BATTERY_PCT}%"
    fi
    DEVICES="${DEVICES}${NAME}${BATTERY} [CONNECTED]\n"
    DEVICE_STATUS["$NAME"]="connected"
  else
    DEVICES="${DEVICES}${NAME}\n"
    DEVICE_STATUS["$NAME"]="disconnected"
  fi
done < <(bluetoothctl devices)

# If no devices found, exit
if [ -z "$DEVICES" ]; then
  echo "No paired devices found" | $HOME/.local/bin/bemenu_runner.sh -n -B1 -l1 -p "Bluetooth"
  exit 1
fi

# Show device selection menu
SELECTED=$(echo -e "$DEVICES" | sed '/^$/d' | $HOME/.local/bin/bemenu_runner.sh -n -B1 -l10 -p "Connect to:")

# If selection was cancelled, exit
if [ -z "$SELECTED" ]; then
  exit 0
fi

# Remove display suffixes (battery icon, percentage and connection status) to get actual device name
DEVICE_NAME=$(echo "$SELECTED" | sed -E 's/ [󰂎󰁺󰁻󰁼󰁽󰁾󰁿󰂀󰂁󰂂󰁹] [0-9]+%| \[CONNECTED\]//g')

# Get MAC address from our stored mapping
MAC="${DEVICE_MACS[$DEVICE_NAME]}"

# Function to get battery info for a device
get_battery_info() {
  local mac="$1"
  local device_info=$(bluetoothctl info "$mac")
  
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
    
    echo " ${battery_icon} ${battery_pct}%"
  else
    echo ""
  fi
}

# Connect or disconnect based on current status
if [ "${DEVICE_STATUS[$DEVICE_NAME]}" = "connected" ]; then
  if bluetoothctl disconnect "$MAC"; then
    notify-send "Bluetooth" "Disconnected from $DEVICE_NAME"
  else
    notify-send "Bluetooth" "Failed to disconnect from $DEVICE_NAME" -u critical
  fi
else
  if bluetoothctl connect "$MAC"; then
    # Get battery info after connection
    sleep 1  # Give device time to report battery status
    BATTERY_INFO=$(get_battery_info "$MAC")
    notify-send "Bluetooth" "Connected to $DEVICE_NAME$BATTERY_INFO"
  else
    notify-send "Bluetooth" "Failed to connect to $DEVICE_NAME" -u critical
  fi
fi