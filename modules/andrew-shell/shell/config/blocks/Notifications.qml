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

      // Inhibited (e.g. auto-inhibit while screensharing) wins over the
      // notification count, so the suppressed state stays visible
      if (SwayNC.isInhibited) {
        return "󰂠"
      }

      if (SwayNC.notificationsCount > 0) {
        return "󱅫"
      }

      return ""
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
