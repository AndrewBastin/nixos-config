pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  property string status: "Disconnected"
  property bool connected: false
  property bool hasInternet: false
  
  Process {
    id: nmStatusProcess
    command: ["nm-status"]
    running: true
    
    stdout: SplitParser {
      onRead: data => {
        try {
          const info = JSON.parse(data)
          connected = info.connected
          hasInternet = info.has_internet
          
          if (!info.connected) {
            status = "Disconnected"
          } else if (info.signal_strength !== undefined) {
            status = `${info.connection_name} ${info.signal_strength}%`
          } else if (info.connection_name) {
            status = info.connection_name
          } else {
            status = "Connected"
          }
        } catch (e) {
          console.error("Failed to parse nm-status output:", e)
        }
      }
    }
  }
}
