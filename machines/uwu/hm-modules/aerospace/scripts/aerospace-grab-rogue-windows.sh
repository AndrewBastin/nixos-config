#!/bin/bash
# Grab rogue windows from disconnected monitors and move them to current workspace
# This is useful when unplugging external monitors

AEROSPACE="/etc/profiles/per-user/andrew/bin/aerospace"

# Get the currently focused workspace
current_workspace=$($AEROSPACE list-workspaces --focused)

# Get number of connected monitors
monitor_list=$($AEROSPACE list-monitors)
monitor_count=$(echo "$monitor_list" | wc -l | tr -d ' ')

# Determine which workspaces should be valid based on monitor count
# Monitor 1: workspaces 1-10, Monitor 2: 11-20, Monitor 3: 21-30, Monitor 4: 31-40
case $monitor_count in
  1) valid_range="1 10" ;;
  2) valid_range="1 20" ;;
  3) valid_range="1 30" ;;
  4) valid_range="1 40" ;;
  *) valid_range="1 40" ;;  # fallback
esac

# Get range bounds
min_ws=$(echo "$valid_range" | awk '{print $1}')
max_ws=$(echo "$valid_range" | awk '{print $2}')

# Process each workspace to find windows
for ws in $(seq 1 40); do
  # Skip if workspace is in valid range
  if [ "$ws" -ge "$min_ws" ] && [ "$ws" -le "$max_ws" ]; then
    continue
  fi
  
  # Check if there are windows on this workspace
  windows_on_ws=$($AEROSPACE list-windows --workspace "$ws" 2>/dev/null)
  if [ -n "$windows_on_ws" ]; then
    # Get window IDs from the output
    echo "$windows_on_ws" | while read -r line; do
      window_id=$(echo "$line" | awk '{print $1}')
      if [ -n "$window_id" ]; then
        echo "Moving window $window_id from workspace $ws to $current_workspace"
        $AEROSPACE move-node-to-workspace --window-id "$window_id" "$current_workspace"
      fi
    done
  fi
done

# Focus the current workspace to ensure we can see the moved windows
$AEROSPACE workspace "$current_workspace"
