pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  property string status: "Disconnected"
  
  function refresh() {
    nmcliProcess.running = true
  }
  
  Process {
    id: nmcliProcess
    command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]
    running: true
    
    stdout: SplitParser {
      onRead: data => {
        // Parse nmcli output to find active connection
        const lines = data.split('\n')
        for (const line of lines) {
          const parts = line.split(':')
          if (parts.length >= 4 && parts[2] === 'connected') {
            const device = parts[0]
            const type = parts[1]
            const connection = parts[3]
            
            // Get signal strength for wifi
            if (type === 'wifi') {
              signalProcess.running = true
            } else {
              status = `${connection} (${type})`
            }
            return
          }
        }
        status = "Disconnected"
      }
    }
  }
  
  Process {
    id: signalProcess
    command: ["nmcli", "-t", "-f", "ACTIVE,SIGNAL,SSID", "device", "wifi"]
    running: false
    
    stdout: SplitParser {
      onRead: data => {
        const lines = data.split('\n')
        for (const line of lines) {
          const parts = line.split(':')
          if (parts.length >= 3 && parts[0] === 'yes') {
            const signal = parts[1]
            const ssid = parts[2]
            status = `${ssid} ${signal}%`
            return
          }
        }
      }
    }
  }
}
