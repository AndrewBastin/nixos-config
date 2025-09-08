import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../singletons"

RowLayout {
  Repeater {
    // `hyprlandMonitor` comes from shell.qml
    model: Hyprland.workspaces.values.filter((x) => x.monitor.id == hyprlandMonitor.id)

    Rectangle {
      id: workspaceParent
      required property HyprlandWorkspace modelData

      color: modelData.active ? Theme.barAccentColor : "transparent"

      implicitWidth: content.implicitWidth + 10
      implicitHeight: content.implicitHeight + 8

      radius: 5

      RowLayout {
        id: content

        anchors.centerIn: parent

        Text {
          id: textItem

          text: workspaceParent.modelData.name
          color: Theme.barTextColor
        }

        Repeater {
          model: workspaceParent.modelData.toplevels

          Item {
            implicitWidth: appIconSource !== ""
              ? imageItem.implicitWidth
              : fallbackItem.implicitWidth

            implicitHeight: appIconSource !== ""
              ? imageItem.implicitHeight
              : fallbackItem.implicitHeight

            required property HyprlandToplevel modelData
            readonly property string appIconSource: {
              // Try directly with the app-id first
              let iconSource = Quickshell.iconPath(modelData.wayland?.appId, true)

              // Try lowercasing the app-id next, for e.g, Slack needs this
              if (iconSource === "") {
                iconSource = Quickshell.iconPath(modelData.wayland?.appId.toLowerCase(), true)
              }

              return iconSource
            }

            // Icon rendered if window icon is found
            Image {
              id: imageItem

              visible: appIconSource !== ""
              enabled: visible

              source: appIconSource
              sourceSize.width: 8
              sourceSize.height: 8

              mipmap: true
            }

            // Fallback Icon
            Text {
              id: fallbackItem

              visible: appIconSource === ""
              enabled: visible

              text: ""
              font.pointSize: Theme.statusIconsFontSize - 2
              color: Theme.barTextColor
            }
          }
        }
      }
    }
  }



  Rectangle {
    implicitWidth: Theme.barSeparatorWidth
    implicitHeight: Theme.barSeparatorHeight

    color: Theme.barSeparatorColor
  }
}
