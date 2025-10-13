pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  property var monitors: ({})
  property var activeWindow: null
  
  Process {
    id: monitorProcess
    command: ["hyprland-info", "--monitor"]
    running: true
    
    stdout: SplitParser {
      onRead: data => {
        try {
          const state = JSON.parse(data)
          monitors = state.monitors || {}
          activeWindow = state.active_window || null
        } catch (e) {
          console.error("HyprlandState: Failed to parse JSON:", e)
        }
      }
    }
    
    onExited: (exitCode, exitStatus) => {
      console.error("HyprlandState: Process exited with code", exitCode)
    }
  }
}
