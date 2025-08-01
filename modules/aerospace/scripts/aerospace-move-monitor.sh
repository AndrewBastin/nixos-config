#!/bin/bash
# Move window to adjacent monitor with fallback logic and focus follow
direction=$1

# Use full path to aerospace binary
AEROSPACE="/etc/profiles/per-user/andrew/bin/aerospace"

# Get the current window ID to track it
current_window=$($AEROSPACE list-windows --focused --format "%{window-id}")

# Try the preferred direction first
$AEROSPACE move-node-to-monitor "$direction" 2>/dev/null
moved=$?

# If that failed, try fallback directions
if [ $moved -ne 0 ]; then
  case "$direction" in
    "left"|"right")
      # Try up first, then down
      $AEROSPACE move-node-to-monitor up 2>/dev/null
      moved=$?
      if [ $moved -ne 0 ]; then
        $AEROSPACE move-node-to-monitor down 2>/dev/null
        moved=$?
      fi
      ;;
    "up"|"down") 
      # Try left first, then right
      $AEROSPACE move-node-to-monitor left 2>/dev/null
      moved=$?
      if [ $moved -ne 0 ]; then
        $AEROSPACE move-node-to-monitor right 2>/dev/null
        moved=$?
      fi
      ;;
  esac
fi

# If the window was successfully moved, focus it
if [ $moved -eq 0 ] && [ -n "$current_window" ]; then
  $AEROSPACE focus --window-id "$current_window" 2>/dev/null
fi