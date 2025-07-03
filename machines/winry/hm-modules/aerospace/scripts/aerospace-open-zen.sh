#!/bin/bash
# Open Zen Browser and ensure it appears on the current workspace

# Check if Zen is running using AppleScript
if osascript -e 'tell application "System Events" to return exists process "zen"' | grep -q "true"; then
    # Zen is running, create new window via menu click
    osascript -e 'tell application "System Events"
        tell process "zen"
            click menu item "New Window" of menu "File" of menu bar 1
        end tell
    end tell'
else
    # Zen is not running, launch it
    open -a "Zen"
fi