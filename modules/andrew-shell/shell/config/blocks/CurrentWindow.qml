import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../singletons"

RowLayout {
  
  readonly property var activeWindow: HyprlandState.activeWindow

  readonly property string appIconSource: {
    const iconName = activeWindow?.icon_name
    return iconName ? Quickshell.iconPath(iconName, true) : ""
  }
  
  Image {
    visible: activeWindow !== null && (appIconSource !== "")
    enabled: visible

    source: appIconSource
    sourceSize.width: 10
    sourceSize.height: 10
  }

  // Fallback Icon
  Text {
    visible: activeWindow !== null && (appIconSource === "")
    enabled: visible

    text: ""
    font.pointSize: Theme.statusIconsFontSize
    color: Theme.barTextColor
  }

  Text {
    function ellipsize(str, n) {
      if (str.length > n) {
        return str.slice(0, n - 3) + '...';
      } else {
        return str;
      }
    }

    visible: activeWindow !== null
    text: ellipsize(activeWindow?.title ?? "", Theme.windowTitleCharsLimit)
    color: Theme.barTextColor
  }
}
