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

  // Either will have the Image source string for the app icon or empty string if a match is not found.
  readonly property string appIconSource: {
    // Try directly with the app-id first
    let iconSource = Quickshell.iconPath(Hyprland.activeToplevel?.wayland?.appId, true)

    // Try lowercasing the app-id next, for e.g, Slack needs this
    if (iconSource === "") {
      iconSource = Quickshell.iconPath(Hyprland.activeToplevel?.wayland?.appId.toLowerCase(), true)
    }

    return iconSource
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
    visible: !reportedTopLevelIsNotThere
    text: Hyprland.activeToplevel?.title ?? ""
    color: Theme.barTextColor
  }
}
