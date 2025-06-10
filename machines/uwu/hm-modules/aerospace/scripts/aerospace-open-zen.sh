#!/bin/bash
# Open Zen Browser and ensure it appears on the current workspace

# Use AppleScript to create a new Zen window via menu
osascript -e 'tell application "System Events"
    tell process "Zen"
        click menu item "New Window" of menu "File" of menu bar 1
    end tell
end tell'