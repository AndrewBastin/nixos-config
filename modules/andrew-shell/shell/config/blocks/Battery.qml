import QtQuick
import Quickshell.Services.UPower
import "../singletons"

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
}
