pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root
  property bool isDnD
  property int notificationsCount
  property bool isPanelVisible
  property bool isInhibited

  Process {
    command: ["swaync-client", "-s"]
    running: true

    stdout: SplitParser {
      onRead: data => {
        var parsedData = JSON.parse(data)

        if (root.isDnD !== parsedData.dnd) {
          root.isDnD = parsedData.dnd
        }

        if (root.notificationsCount !== parsedData.count) {
          root.notificationsCount = parsedData.count
        }

        if (root.isPanelVisible !== parsedData.visible) {
          root.isPanelVisible = parsedData.visible
        }

        if (root.isInhibited !== parsedData.inhibited) {
          root.isInhibited = parsedData.inhibited
        }
      }
    }
  }
}
