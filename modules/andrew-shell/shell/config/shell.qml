pragma ComponentBehavior: Bound
//@ pragma UseQApplication

import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "blocks" as Blocks
import "components" as Components
import "singletons"

Scope {
  id: root

  property string dateTime
  
  Variants {
    model: Quickshell.screens;

    Scope {
      required property var modelData
      
      PanelWindow {
        id: rootWindow

        property var hyprlandMonitor: Hyprland.monitorFor(modelData)

        anchors {
          top: true
          left: true
          right: true
        }

        screen: modelData

        implicitHeight: 33

        color: Theme.barBgColor

        Components.TooltipProvider {
          window: rootWindow
          anchors.fill: parent
          
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

              Blocks.Workspaces {
                property var hyprlandMonitor: rootWindow.hyprlandMonitor
              }
              Blocks.CurrentWindow {
                property var hyprlandMonitor: rootWindow.hyprlandMonitor
              }
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
  }
}
