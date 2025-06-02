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
  
  # Check if device is connected
  if bluetoothctl info "$MAC" | grep -q "Connected: yes"; then
    DEVICES="${DEVICES}${NAME} [CONNECTED]\n"
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

# Remove display suffix to get actual device name
DEVICE_NAME=$(echo "$SELECTED" | sed 's/ \[CONNECTED\]$//')

# Get MAC address from our stored mapping
MAC="${DEVICE_MACS[$DEVICE_NAME]}"

# Connect or disconnect based on current status
if [ "${DEVICE_STATUS[$DEVICE_NAME]}" = "connected" ]; then
  if bluetoothctl disconnect "$MAC"; then
    notify-send "Bluetooth" "Disconnected from $DEVICE_NAME"
  else
    notify-send "Bluetooth" "Failed to disconnect from $DEVICE_NAME" -u critical
  fi
else
  if bluetoothctl connect "$MAC"; then
    notify-send "Bluetooth" "Connected to $DEVICE_NAME"
  else
    notify-send "Bluetooth" "Failed to connect to $DEVICE_NAME" -u critical
  fi
fi