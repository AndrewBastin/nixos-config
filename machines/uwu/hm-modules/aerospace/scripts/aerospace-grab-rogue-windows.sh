#!/bin/bash
# Grab rogue windows from disconnected monitors and move them to current workspace
# This is useful when unplugging external monitors

AEROSPACE="/etc/profiles/per-user/andrew/bin/aerospace"

# Get the currently focused workspace
current_workspace=$($AEROSPACE list-workspaces --focused)

# Get all windows with their workspace assignments
all_windows=$($AEROSPACE list-windows --all --format "%{window-id}:%{workspace}")

# Get list of valid workspaces (visible on connected monitors)
valid_workspaces=$($AEROSPACE list-workspaces --monitor all)

# Process each window
while IFS=: read -r window_id workspace; do
  # Skip if window has no workspace (shouldn't happen but be safe)
  if [ -z "$workspace" ]; then
    continue
  fi
  
  # Check if the window's workspace is valid (visible on a connected monitor)
  if ! echo "$valid_workspaces" | grep -q "^$workspace$"; then
    # This window is on a disconnected monitor's workspace, move it to current workspace
    echo "Moving window $window_id from invalid workspace $workspace to $current_workspace"
    $AEROSPACE move-node-to-workspace --window-id "$window_id" "$current_workspace"
  fi
done <<< "$all_windows"

# Focus the current workspace to ensure we can see the moved windows
$AEROSPACE workspace "$current_workspace"