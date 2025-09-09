pragma ComponentBehavior: Bound
//@ pragma UseQApplication

import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "blocks" as Blocks
import "singletons"

Scope {
  id: root

  property string dateTime
  
  Variants {
    model: Quickshell.screens;

    PanelWindow {
      id: rootWindow
      required property var modelData

      property var hyprlandMonitor: Hyprland.monitorFor(modelData)

      anchors {
        top: true
        left: true
        right: true
      }

      screen: modelData

      implicitHeight: 33

      color: Theme.barBgColor

      RowLayout {
        anchors {
          fill: parent
          leftMargin: 10
          rightMargin: 10
        }

        // Left Items
        RowLayout {
          Layout.alignment: Qt.AlignLeft
          Layout.fillWidth: true

          Blocks.Workspaces {}
          Blocks.CurrentWindow {}
        }

        // Right Items
        RowLayout {
          Layout.alignment: Qt.AlignRight
          Layout.fillWidth: true
          spacing: Theme.statusIconsSpacing
          
          Blocks.ConcealedGroup {}
          Blocks.Audio {}
          Blocks.Network {}
          Blocks.Battery {}
          Blocks.Notifications {}
          Blocks.Clock {}
        }
      }
    }
  }
}
