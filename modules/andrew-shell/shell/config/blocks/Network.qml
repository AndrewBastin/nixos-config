import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../singletons"
import "../components" as Components

// HACK: The implementation here is a pretty hacky one.
// The way this is implemented is that, we render the `nm-applet` systray applet here and override its icons
// Click events also get directed to its menu.

Repeater {
    model: ScriptModel {
      values: SystemTray.items.values.filter((x) => x.id === "nm-applet")
    }

    MouseArea {
      implicitWidth: child.implicitWidth
      implicitHeight: child.implicitHeight

      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true

      required property SystemTrayItem modelData
      
      onEntered: {
        NetworkStatus.refresh()
      }

    Text {
        id: child
        anchors.centerIn: parent

        text: {
          var icon = parent.modelData.icon

          // NOTE: This is not gonna be all of them, as needed, fill this in
          if (icon.endsWith("nm-signal-100")) return "󰣺"
          if (icon.endsWith("nm-signal-75")) return "󰣸"
          if (icon.endsWith("nm-signal-50")) return "󰣶"
          if (icon.endsWith("nm-signal-25")) return "󰣴"
          if (icon.endsWith("nm-signal-00")) return "󰣾"
          if (icon.endsWith("nm-no-connection")) return "󰌙"
          if (icon.includes("nm-stage")) return ""

          return icon
        }
        color: Theme.barTextColor
        font.pointSize: Theme.statusIconsFontSize
        
        Components.Tooltip {
          text: NetworkStatus.status
        }
      }

      acceptedButtons: Qt.LeftButton

      onClicked: (mouse) => {
        // NOTE: We are straight on only using the menu implementation rather than activates
        // since nm-applet only supports the menu and since this systray is specifically only for nm-applet,
        // this onClicked behavior shouldn't be generalized for the rest

        // Mouse points are relative to the mouse area
        const {x, y} = this.mapToGlobal(mouse.x + Theme.systrayMenuOffsetX, mouse.y + Theme.systrayMenuOffsetY)

        modelData.display(rootWindow, x, y)
      }
    }
}
