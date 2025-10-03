import QtQuick
import "../singletons"

MouseArea {
  id: root
  
  property string text: ""
  
  anchors.fill: parent
  hoverEnabled: true
  propagateComposedEvents: true
  
  function findTooltipWindow() {
    var item = parent
    while (item) {
      if (item.tooltipWindow !== undefined) {
        return item.tooltipWindow
      }
      item = item.parent
    }
    return null
  }
  
  onEntered: {
    const window = findTooltipWindow()
    if (window && text) {
      TooltipManager.show(parent, text, window)
    }
  }
  
  onExited: {
    TooltipManager.hide()
  }
}
