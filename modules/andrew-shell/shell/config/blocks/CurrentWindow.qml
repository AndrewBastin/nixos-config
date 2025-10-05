import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../singletons"

RowLayout {
  
  // Hyprland.activeToplevel has a tendency to not be up-to-date
  // Particularly in the case where the top level gets closed and no other top levels are focused.
  // In those cases, we are gonna assume there is no focus and blank out the output
  // `hyprlandMonitor` comes from shell.qml
  readonly property bool reportedTopLevelIsNotThere: {
    // Ideally this should be just one
    const reportedTopLevel = Hyprland.activeToplevel

    // NOTE: If nothing is there, we are just gonna say no.
    if (reportedTopLevel === null) return true

    const workspaces = Hyprland.workspaces.values
        .filter((x) => x.monitor.id == hyprlandMonitor.id && x.focused);

    for (const workspace of workspaces) {
      for (const toplevel of workspace.toplevels.values) {
        // If their address match then we should be okay
        if (toplevel.address === reportedTopLevel.address) {
          return false
        }
      }
    }

    return true
  }

  readonly property string appIconSource: {
    const iconName = IconResolver.resolveIcon(Hyprland.activeToplevel?.wayland?.appId)
    return iconName ? Quickshell.iconPath(iconName, true) : ""
  }
  
  Image {
    visible: !reportedTopLevelIsNotThere && (appIconSource !== "")
    enabled: visible

    source: appIconSource
    sourceSize.width: 10
    sourceSize.height: 10
  }

  // Fallback Icon
  Text {
    visible: !reportedTopLevelIsNotThere && (appIconSource === "")
    enabled: visible

    text: ""
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

    visible: !reportedTopLevelIsNotThere
    text: ellipsize(Hyprland.activeToplevel?.title ?? "", Theme.windowTitleCharsLimit)
    color: Theme.barTextColor
  }
}
