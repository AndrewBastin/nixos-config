import Quickshell
import QtQuick
import "../singletons"

MouseArea {
  width: innerContent.implicitWidth
  height: innerContent.implicitHeight

  cursorShape: Qt.PointingHandCursor

  Text {
    id: innerContent
    
    text: {
      // If DnD, always show the DnD icon
      if (SwayNC.isDnD) {
        return "󰂛"
      }

      // If we have a notification, show the has notification icon, even if inhibited
      if (SwayNC.notificationsCount > 0) {
        return "󱅫"
      }

      return SwayNC.isInhibited
        ? "󰂠"
        : ""
    }
    color: Theme.barTextColor
    font.pointSize: Theme.statusIconsFontSize
  }

  acceptedButtons: Qt.LeftButton | Qt.RightButton

  onClicked: (mouse) => {
    if (mouse.button === Qt.LeftButton) {
      Quickshell.execDetached(["hyprctl", "dispatch", "exec", "swaync-client -t"])
    } else if (mouse.button === Qt.RightButton) {
      Quickshell.execDetached(["hyprctl", "dispatch", "exec", "swaync-client -d"])
    }
  }
}
