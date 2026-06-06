pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  // Upcoming events within the next 24h: [{ title, start, end, calendar, url? }]
  // where start/end are epoch seconds. Sorted by start, pre-filtered
  // (no all-day, cancelled, declined, or holiday-calendar events).
  property var events: []

  // Start time (epoch secs) of an event the user dismissed via right-click;
  // the widget stays hidden for that event but shows for any other.
  property real dismissedStart: 0

  Process {
    id: calendarStatusProcess
    command: ["calendar-status", "--exclude-calendar", "Holidays in"]
    running: true

    stdout: SplitParser {
      onRead: data => {
        try {
          const info = JSON.parse(data)
          events = info.events ?? []
        } catch (e) {
          console.error("Failed to parse calendar-status output:", e)
        }
      }
    }
  }
}
