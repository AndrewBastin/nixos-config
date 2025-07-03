#!/bin/bash
# Open Finder and ensure new window appears on the current workspace

# Use AppleScript to create a new Finder window
osascript -e 'tell application "Finder"
    make new Finder window
    activate
end tell'