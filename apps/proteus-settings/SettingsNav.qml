pragma Singleton

import Quickshell
import QtQuick
import "shared"

// Settings navigation — go in (leaf), back out (category), jump (sidebar).
Singleton {
  id: root

  property string page: "style"

  // Install… seed travels with navigation (same singleton as page) so sticky
  // Software loaders always see it — do not rely on Packages alone.
  property string pendingInstallQuery: ""
  property string pendingInstallLeaf: ""
  property int pendingInstallEpoch: 0

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
    },
    {
      id: "network",
      label: "Network"
    },
    {
      id: "privacy",
      label: "Privacy & security"
    },
    {
      id: "accounts",
      label: "Online accounts"
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

  function hasPendingInstall(leafKey) {
    return pendingInstallQuery.length > 0
        && pendingInstallLeaf === String(leafKey || "")
  }

  function takePendingInstall(leafKey) {
    if (!hasPendingInstall(leafKey))
      return ""
    const q = pendingInstallQuery
    pendingInstallQuery = ""
    pendingInstallLeaf = ""
    return q
  }

  // Escape Install… → Software leaf with a seeded Install search (same window).
  function goInstallSearch(query, leafId) {
    const leaf = String(leafId || "packages-search").trim() || "packages-search"
    const q = String(query || "").trim()
    pendingInstallLeaf = leaf
    pendingInstallQuery = q
    pendingInstallEpoch++
    // Navigate first — seed is on this singleton; Packages mirror is best-effort.
    go(leaf)
    try {
      Packages.seedPackageSearch(q, leaf)
    } catch (e) {
    }
  }

  function close() {
    Qt.quit()
  }

  function applyDeepLinkFromEnv() {
    const raw = Quickshell.env("PROTEUS_SETTINGS_PAGE")
    const q = String(Quickshell.env("PROTEUS_SETTINGS_QUERY") || "").trim()
    const id = String(raw || "").trim()
    if (q.length) {
      const leaf = id.length ? id : "packages-search"
      pendingInstallLeaf = (leaf === "packages-aur" || leaf === "packages-flatpak")
          ? leaf
          : "packages-search"
      pendingInstallQuery = q
      pendingInstallEpoch++
      try {
        Packages.seedPackageSearch(q, pendingInstallLeaf)
      } catch (e) {
      }
    }
    if (!id.length)
      return
    go(id)
  }

  Component.onCompleted: applyDeepLinkFromEnv()
}
