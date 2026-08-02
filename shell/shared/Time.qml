pragma Singleton

import Quickshell
import QtQuick

Singleton {
  // Menu-bar clock pieces — weekday + date + 12h time (macOS-adjacent).
  readonly property string dateText: Qt.formatDateTime(clock.date, "ddd MMM d")
  readonly property string timeText: Qt.formatDateTime(clock.date, "h:mm AP")
  // Combined form (legacy / single-line callers)
  readonly property string text: dateText + "  " + timeText

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
}
