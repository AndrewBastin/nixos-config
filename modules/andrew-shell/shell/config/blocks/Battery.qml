import QtQuick
import Quickshell.Services.UPower
import "../singletons"
import "../components" as Components

Text {
  text: {
    const percent = Math.ceil(UPower.displayDevice.percentage * 100)

    if (percent <= 5) return "󰂎"
    if (percent <= 10) return "󰁺"
    if (percent <= 20) return "󰁻"
    if (percent <= 30) return "󰁼"
    if (percent <= 40) return "󰁽"
    if (percent <= 50) return "󰁾" 
    if (percent <= 60) return "󰁿" 
    if (percent <= 70) return "󰂀"
    if (percent <= 80) return "󰂁" 
    if (percent <= 95) return "󰂂"
    
    return "󰁹"
  }
  color: Theme.barTextColor
  font.pointSize: Theme.statusIconsFontSize
  
  Components.Tooltip {
    text: {
      const percent = Math.ceil(UPower.displayDevice.percentage * 100)
      const isCharging = UPower.displayDevice.state === UPowerDevice.Charging
      
      let status = ""
      if (isCharging) {
        const timeToFull = UPower.displayDevice.timeToFull
        if (timeToFull > 0) {
          const hours = Math.floor(timeToFull / 3600)
          const minutes = Math.floor((timeToFull % 3600) / 60)
          const timeStr = hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`
          status = `Charging - ${timeStr} until full`
        } else {
          status = "Charging"
        }
      } else {
        const timeToEmpty = UPower.displayDevice.timeToEmpty
        if (timeToEmpty > 0) {
          const hours = Math.floor(timeToEmpty / 3600)
          const minutes = Math.floor((timeToEmpty % 3600) / 60)
          const timeStr = hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`
          status = `${timeStr} remaining`
        }
      }
      
      return `${percent}% ${status}`.trim()
    }
  }
}
