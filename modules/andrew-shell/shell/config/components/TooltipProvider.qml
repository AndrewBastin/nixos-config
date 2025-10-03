import QtQuick
import Quickshell
import "../singletons"

Item {
  id: root
  
  property var window: null
  
  // Provide the window to all children via this property
  property var tooltipWindow: window
  
  // The tooltip popup is now owned by the provider
  PopupWindow {
    id: tooltipPopup
    
    // Only show for this provider's window
    visible: TooltipManager.visible
             && root.window
             && TooltipManager.currentWindow === root.window
    
    // Anchor to the provider's window
    anchor.window: root.window
    anchor.rect.x: TooltipManager.currentItem
                   ? TooltipManager.currentItem.mapToItem(root.window.contentItem, 0, 0).x
                   : 0
    anchor.rect.y: TooltipManager.currentItem
                   ? TooltipManager.currentItem.mapToItem(root.window.contentItem, 0, 0).y
                     + TooltipManager.currentItem.height
                   : 0
    anchor.rect.width: TooltipManager.currentItem ? TooltipManager.currentItem.width : 1
    anchor.rect.height: 1
    
    implicitWidth: tooltipText.implicitWidth + Theme.tooltipPaddingX * 2
    implicitHeight: tooltipText.implicitHeight + Theme.tooltipPaddingY * 2
    
    color: Theme.tooltipBgColor
    
    Text {
      id: tooltipText
      x: Theme.tooltipPaddingX
      y: Theme.tooltipPaddingY
      text: TooltipManager.currentText
      color: Theme.tooltipTextColor
      font.pointSize: 10
    }
  }
}
