import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../singletons"

RowLayout {
  Repeater {
    // `hyprlandMonitor` comes from shell.qml
    model: Hyprland.workspaces.values.filter((x) => x.monitor.id == hyprlandMonitor.id || x.name == "special:magic")

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

          text: {
            if (workspaceParent.modelData.name !== "special:magic") {
              return workspaceParent.modelData.name
            } else {
              return "SP"
            }
          }
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
              const iconName = IconResolver.resolveIcon(modelData.wayland?.appId)
              return iconName ? Quickshell.iconPath(iconName, true) : ""
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
