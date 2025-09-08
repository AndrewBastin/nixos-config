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

          Image {
            required property HyprlandToplevel modelData

            source: {
              var iconSource = Quickshell.iconPath(modelData.wayland?.appId, true)

              if (iconSource === "") {
                iconSource = Quickshell.iconPath(modelData.wayland?.appId.toLowerCase())
              }

              return iconSource
            }
            sourceSize.width: 8
            sourceSize.height: 8

            mipmap: true
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
