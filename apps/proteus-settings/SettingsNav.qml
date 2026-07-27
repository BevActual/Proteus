pragma Singleton

import Quickshell
import QtQuick

// Settings navigation — go in (leaf), back out (category), jump (sidebar).
Singleton {
  id: root

  property string page: "style"

  readonly property bool canGoBack: page.startsWith("style-")
      || page.startsWith("desktop-")
      || page.startsWith("peripherals-")
      || page.startsWith("packages-")

  readonly property string backLabel: {
    if (page.startsWith("desktop-"))
      return "Desktop"
    if (page.startsWith("style-"))
      return "Appearance"
    if (page.startsWith("peripherals-"))
      return "Peripherals"
    if (page.startsWith("packages-"))
      return "Software"
    return ""
  }

  readonly property string section: {
    if (page === "style" || page.startsWith("style-"))
      return "style"
    if (page === "desktop" || page.startsWith("desktop-"))
      return "desktop"
    if (page === "peripherals" || page.startsWith("peripherals-") || page === "keyboard")
      return "peripherals"
    if (page === "packages" || page.startsWith("packages-"))
      return "packages"
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
    if (page.startsWith("style-")) {
      page = "style"
      return true
    }
    if (page.startsWith("desktop-")) {
      page = "desktop"
      return true
    }
    if (page.startsWith("peripherals-") || page === "keyboard") {
      page = "peripherals"
      return true
    }
    if (page.startsWith("packages-")) {
      page = "packages"
      return true
    }
    return false
  }

  function goSection(id) {
    go(id)
  }

  function close() {
    Qt.quit()
  }
}
