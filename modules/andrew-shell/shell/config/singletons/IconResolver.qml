pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  property var iconMappings: ({})
  
  function resolveIcon(appId) {
    if (!appId) return ""
    
    if (iconMappings[appId]) {
      return iconMappings[appId]
    }
    
    return ""
  }
  
  Process {
    id: iconResolverProcess
    command: ["hyprland-icon-resolver", "--watch"]
    running: true
    
    stdout: SplitParser {
      onRead: data => {
        try {
          const mappings = JSON.parse(data)
          iconMappings = mappings
        } catch (e) {
          console.error("IconResolver: Failed to parse JSON:", e)
        }
      }
    }
  }
}
