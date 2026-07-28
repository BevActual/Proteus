pragma Singleton

import Quickshell
import QtQuick

// Settings navigation — go in (leaf), back out (category), jump (sidebar).
Singleton {
  id: root

  property string page: "style"

  // Categories that drill in: page ids are "<id>" for the list and "<id>-*" for
  // each leaf. Registering a hub here is all that back / breadcrumb / sidebar
  // highlighting need — they used to hardcode the same four prefixes each.
  readonly property var hubs: [
    {
      id: "style",
      label: "Appearance"
    },
    {
      id: "desktop",
      label: "Desktop"
    },
    {
      id: "peripherals",
      label: "Peripherals"
    },
    {
      id: "packages",
      label: "Software"
    },
    {
      id: "sound",
      label: "Sound"
    }
  ]

  // The hub a leaf page belongs to, or null on a top-level page.
  readonly property var activeHub: {
    for (let i = 0; i < hubs.length; i++) {
      if (page.startsWith(hubs[i].id + "-"))
        return hubs[i]
    }
    return null
  }

  readonly property bool canGoBack: !!activeHub

  readonly property string backLabel: activeHub ? String(activeHub.label) : ""

  readonly property string section: {
    // Legacy top-level Keyboard lives under Peripherals.
    if (page === "keyboard")
      return "peripherals"
    for (let i = 0; i < hubs.length; i++) {
      const id = hubs[i].id
      if (page === id || page.startsWith(id + "-"))
        return id
    }
    return page
  }

  function go(id) {
    if (!id || !String(id).length)
      return
    // Legacy top-level Keyboard → Peripherals → Keyboard
    if (id === "keyboard")
      id = "peripherals-keyboard"
    page = String(id)
  }

  function back() {
    if (page === "keyboard") {
      page = "peripherals"
      return true
    }
    const hub = activeHub
    if (!hub)
      return false
    page = String(hub.id)
    return true
  }

  function goSection(id) {
    go(id)
  }

  function close() {
    Qt.quit()
  }
}
