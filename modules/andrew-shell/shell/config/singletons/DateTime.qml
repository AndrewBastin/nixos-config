pragma Singleton

import Quickshell
import QtQuick

Singleton {
  readonly property string dateTime: {
    Qt.formatDateTime(clock.date, "ddd MMM dd h:mm AP")
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
}
