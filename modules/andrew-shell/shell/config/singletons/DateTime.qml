pragma Singleton

import Quickshell
import QtQuick

Singleton {
  readonly property date now: clock.date
  readonly property string dateTime: {
    Qt.formatDateTime(clock.date, "ddd MMM dd h:mm AP")
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
}
