pragma Singleton

import Quickshell
import QtQuick

// Read PROTEUS_ADAPT_* from this process environment (set at Dock/Beacon /
// openSettings launch). Soft consumer helper — never gates availability.
Singleton {
  id: root

  readonly property string input: {
    const v = Quickshell.env("PROTEUS_ADAPT_INPUT")
    return v && String(v).length ? String(v) : ""
  }
  readonly property string nav: {
    const v = Quickshell.env("PROTEUS_ADAPT_NAV")
    return v && String(v).length ? String(v) : ""
  }
  readonly property string panes: {
    const v = Quickshell.env("PROTEUS_ADAPT_PANES")
    return v && String(v).length ? String(v) : ""
  }

  readonly property bool present: input.length > 0 || nav.length > 0 || panes.length > 0

  readonly property string summary: {
    if (!present)
      return ""
    const bits = []
    if (input.length)
      bits.push(input)
    if (nav.length)
      bits.push(nav + " nav")
    if (panes.length)
      bits.push(panes + " panes")
    return bits.join(" · ")
  }

  readonly property string hint: present
      ? ("Launch adapt · " + summary)
      : "No PROTEUS_ADAPT_* in this process — open Settings from Dock/Beacon for inject"
}
