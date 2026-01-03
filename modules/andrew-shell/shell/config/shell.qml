pragma ComponentBehavior: Bound
//@ pragma UseQApplication

import Quickshell
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

        property string monitorName: modelData.name

        anchors {
          top: !VmMode.enabled
          bottom: VmMode.enabled
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
                property string monitorName: rootWindow.monitorName
              }
              Blocks.CurrentWindow {}
            }

            // Right Items
            RowLayout {
              Layout.alignment: Qt.AlignRight
              Layout.fillWidth: true
              spacing: Theme.statusIconsSpacing
              
              Blocks.ConcealedGroup {}
              Blocks.Audio { visible: !VmMode.enabled }
              Blocks.Network { visible: !VmMode.enabled }
              Blocks.Battery { visible: !VmMode.enabled }
              Blocks.Notifications {}
              Blocks.Clock { visible: !VmMode.enabled }
            }
          }
        }
      }
    }
  }
}
