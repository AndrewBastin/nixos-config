import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../singletons"

RowLayout {
  Image {
    source: {
      var iconSource = Quickshell.iconPath(Hyprland.activeToplevel?.wayland?.appId, true)

      if (iconSource === "") {
        iconSource = Quickshell.iconPath(Hyprland.activeToplevel?.wayland?.appId.toLowerCase())
      }

      return iconSource
    }
    sourceSize.width: 10
    sourceSize.height: 10
  }

  Text {
    text: Hyprland.activeToplevel?.title ?? ""
    color: Theme.barTextColor
  }
}
