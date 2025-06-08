#!/bin/bash
# Get focused monitor ID and calculate workspace offset dynamically
AEROSPACE="/etc/profiles/per-user/andrew/bin/aerospace"
monitor_id=$($AEROSPACE list-monitors --focused | cut -d' ' -f1)
workspace_num=$1

# Get all monitor IDs and sort them to create consistent ordering
all_monitors=$($AEROSPACE list-monitors | cut -d' ' -f1 | sort -n)

# Find the position of current monitor in the sorted list (0-based)
monitor_position=0
for mid in $all_monitors; do
  if [ "$mid" = "$monitor_id" ]; then
    break
  fi
  monitor_position=$((monitor_position + 1))
done

# Calculate workspace offset: monitor 0 = 1-10, monitor 1 = 11-20, etc.
offset=$((monitor_position * 10))
target_workspace=$((offset + workspace_num))

# Handle workspace 0 as workspace 10 in each range
if [ "$workspace_num" -eq 0 ]; then
  target_workspace=$((offset + 10))
fi

$AEROSPACE workspace "$target_workspace"
