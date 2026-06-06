import QtQuick
import Quickshell
import "../singletons"
import "../components" as Components

Text {
  id: root

  // Toggled briefly after a Ctrl+Click copies the meeting link, to show a
  // checkmark instead of the countdown.
  property bool copied: false

  // First event that hasn't started yet and isn't the one the user dismissed;
  // re-evaluates every minute via DateTime.now (minute-precision SystemClock)
  // and whenever the CalendarStatus event list refreshes.
  readonly property var nextEvent: {
    const nowSecs = DateTime.now.getTime() / 1000
    return CalendarStatus.events.find(e =>
      e.start > nowSecs && e.start !== CalendarStatus.dismissedStart) ?? null
  }
  readonly property int minutesUntil: nextEvent
    ? Math.ceil((nextEvent.start - DateTime.now.getTime() / 1000) / 60)
    : 0

  // NOTE: visibility must live here (not at the use site in shell.qml) —
  // an instance-site `visible:` would override this whole binding.
  // SwayNC.stateReceived guards against a brief flash on shell startup,
  // before the actual DnD/inhibited state has arrived.
  visible: !VmMode.enabled && SwayNC.stateReceived
    && !SwayNC.isDnD && !SwayNC.isInhibited
    && nextEvent !== null && minutesUntil <= 60
  // En space ( ) after the regular space, for extra gap between the
  // glyph and the countdown
  text: copied ? "󰄬" : `󰃭  ${minutesUntil}m`
  color: Theme.barTextColor
  font.pointSize: Theme.statusIconsFontSize

  Timer {
    id: copiedReset
    interval: 1500
    onTriggered: root.copied = false
  }

  Components.Tooltip {
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    text: {
      if (!root.nextEvent) return ""
      const startTime = Qt.formatTime(new Date(root.nextEvent.start * 1000), "h:mm AP")
      const line = `${root.nextEvent.title} · ${startTime} (${root.nextEvent.calendar})`
      return line + (root.nextEvent.url
        ? "\n\nClick: copy meeting link · Middle-click: open Thunderbird · Right-click: dismiss"
        : "\n\nMiddle-click: open Thunderbird · Right-click: dismiss")
    }
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) {
        CalendarStatus.dismissedStart = root.nextEvent.start
      } else if (mouse.button === Qt.MiddleButton) {
        Quickshell.execDetached(["hyprctl", "dispatch", "exec", "thunderbird -calendar"])
      } else if (root.nextEvent.url) {
        Quickshell.clipboardText = root.nextEvent.url
        root.copied = true
        copiedReset.restart()
      }
    }
  }
}
