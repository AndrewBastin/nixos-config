import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import "../singletons"

Item {
  id: root
  
  // Properties
  property bool expanded: false
  property int animationDuration: 250
  
  // Calculate required dimensions
  implicitWidth: mainLayout.implicitWidth
  implicitHeight: mainLayout.implicitHeight
  
  RowLayout {
    id: mainLayout
    anchors.fill: parent
    
    // Toggle button for expanding/collapsing
    MouseArea {
      id: toggleButton
      implicitWidth: chevron.implicitWidth
      implicitHeight: chevron.implicitHeight
      cursorShape: Qt.PointingHandCursor
      
      Text {
        id: chevron
        anchors.centerIn: parent
        text: "󰅁" 
        color: Theme.barSeparatorColor
        font.pointSize: Theme.statusIconsFontSize + 4
        
        // Rotation animation for the chevron
        rotation: root.expanded ? 180 : 0
        Behavior on rotation {
          NumberAnimation {
            duration: root.animationDuration
            easing.type: Easing.InOutQuad
          }
        }
      }
      
      onClicked: {
        root.expanded = !root.expanded
      }
    }
    
    // Collapsible icons container
    Item {
      id: collapsibleContainer
      Layout.preferredWidth: expanded ? iconsLayout.implicitWidth : 0
      Layout.fillHeight: true
      clip: true
      
      // Animate width changes for slide effect
      Behavior on Layout.preferredWidth {
        NumberAnimation {
          duration: root.animationDuration
          easing.type: Easing.InOutQuad
        }
      }
      
      RowLayout {
        id: iconsLayout
        spacing: Theme.statusIconsSpacing
        anchors.verticalCenter: parent.verticalCenter
        opacity: root.expanded ? 1.0 : 0.0
        
        // Fade in/out animation
        Behavior on opacity {
          NumberAnimation {
            duration: root.animationDuration
            easing.type: Easing.InOutQuad
          }
        }
        
        Repeater {
          // All system tray icons except nm-applet
          model: SystemTray.items.values.filter((x) => x.id !== "nm-applet")
          
          MouseArea {
            implicitWidth: child.implicitWidth
            implicitHeight: child.implicitHeight
            required property SystemTrayItem modelData
            
            Image {
              id: child
              anchors.centerIn: parent
              source: parent.modelData.icon
              sourceSize.width: 14
              sourceSize.height: 14
            }
            
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
              // Mouse points are relative to the mouse area, converting it to global coords
              const {x, y} = this.mapToGlobal(
                mouse.x + Theme.systrayMenuOffsetX, 
                mouse.y + Theme.systrayMenuOffsetY
              )
              if (mouse.button === Qt.LeftButton) {
                if (modelData.onlyMenu) {
                  modelData.display(rootWindow, x, y)
                } else {
                  modelData.activate()
                }
              } else if (mouse.button === Qt.RightButton) {
                if (modelData.hasMenu) {
                  modelData.display(rootWindow, x, y)
                } else {
                  modelData.secondaryActivate()
                }
              }
            }
          }
        }
        
        // Trailing separator - now inside the collapsible container
        Rectangle {
          implicitWidth: Theme.barSeparatorWidth
          implicitHeight: Theme.barSeparatorHeight
          color: Theme.barSeparatorColor
        }
      }
    }
  }
  
  // States for expanded/collapsed
  states: [
    State {
      name: "collapsed"
      when: !root.expanded
      PropertyChanges {
        target: collapsibleContainer
        Layout.preferredWidth: 0
      }
      PropertyChanges {
        target: iconsLayout
        opacity: 0.0
      }
    },
    State {
      name: "expanded"
      when: root.expanded
      PropertyChanges {
        target: collapsibleContainer
        Layout.preferredWidth: iconsLayout.implicitWidth
      }
      PropertyChanges {
        target: iconsLayout
        opacity: 1.0
      }
    }
  ]
  
  transitions: [
    Transition {
      from: "collapsed"
      to: "expanded"
      reversible: true
      
      ParallelAnimation {
        NumberAnimation {
          target: collapsibleContainer
          property: "Layout.preferredWidth"
          duration: root.animationDuration
          easing.type: Easing.InOutQuad
        }
        NumberAnimation {
          target: iconsLayout
          property: "opacity"
          duration: root.animationDuration
          easing.type: Easing.InOutQuad
        }
      }
    }
  ]
}
