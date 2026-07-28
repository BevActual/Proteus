pragma Singleton

import Quickshell
import QtQuick

Singleton {
  // Menu-bar clock — weekday + 12h time (macOS-adjacent, not 24h military)
  readonly property string text: {
    const d = clock.date
    const day = Qt.formatDateTime(d, "ddd")
    const time = Qt.formatDateTime(d, "h:mm AP")
    return day + "  " + time
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
}
