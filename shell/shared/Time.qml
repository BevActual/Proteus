pragma Singleton

import Quickshell
import QtQuick

Singleton {
  readonly property string text: Qt.formatDateTime(clock.date, "ddd  hh:mm")

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
}
