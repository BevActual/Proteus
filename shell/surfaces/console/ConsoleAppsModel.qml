import Quickshell
import QtQuick
import "../../shared"

// DesktopEntries → console Library / Search cards.
QtObject {
  id: root

  property string query: ""

  readonly property var palette: [
    { color0: "#1a3a5c", color1: "#0d1828" },
    { color0: "#1a5c3a", color1: "#0d2818" },
    { color0: "#5c3a1a", color1: "#28180d" },
    { color0: "#3a1a5c", color1: "#1c0d28" },
    { color0: "#1a4a5c", color1: "#0d2228" },
    { color0: "#2a2a2e", color1: "#141416" }
  ]

  function colorFor(name) {
    const s = String(name || "")
    let h = 0
    for (let i = 0; i < s.length; i++)
      h = (h + s.charCodeAt(i) * (i + 1)) % 997
    return root.palette[h % root.palette.length]
  }

  function isHiddenEntry(a) {
    if (!a || !a.name)
      return true
    try {
      if (a.noDisplay)
        return true
    } catch (e) {
    }
    const id = String(a.id || "").toLowerCase()
    const name = String(a.name || "").toLowerCase()
    // Skip chrome / helpers that don't belong in console Library
    if (id.indexOf("proteus-settings") >= 0)
      return false // Settings is useful from console
    if (id === "quickshell" || name === "quickshell")
      return true
    if (id.indexOf("wayland") >= 0 && id.indexOf("session") >= 0)
      return true
    return false
  }

  readonly property var allApps: {
    const apps = DesktopEntries.applications.values
    const out = []
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      if (root.isHiddenEntry(a))
        continue
      if (EnvGate && typeof EnvGate.appAvailable === "function" && !EnvGate.appAvailable(a))
        continue
      const id = String(a.id || "")
      const title = String(a.name || id)
      const colors = root.colorFor(title)
      let tag = "APP"
      let needsGs = false
      try {
        const cats = a.categories || []
        const catStr = (cats && cats.length) ? cats.join(";").toLowerCase() : ""
        if (catStr.indexOf("game") >= 0) {
          tag = "GAMES"
          needsGs = true
        } else if (cats && cats.length) {
          tag = String(cats[0]).toUpperCase().slice(0, 12)
        }
      } catch (e) {
      }
      const idLower = id.toLowerCase()
      if (idLower.indexOf("steam") >= 0 || idLower.indexOf("retroarch") >= 0) {
        tag = "GAMES"
        needsGs = true
      }
      if (idLower.indexOf("proteus-web-") === 0)
        tag = "WEB"
      out.push({
        id: id,
        title: title,
        tag: tag,
        color0: colors.color0,
        color1: colors.color1,
        desktopId: id,
        kind: "desktop",
        needsGamescope: needsGs,
        commandArgs: [],
        meta: id
      })
    }
    out.sort((x, y) => String(x.title).localeCompare(String(y.title)))
    return out
  }

  readonly property var filtered: {
    const q = String(root.query || "").trim().toLowerCase()
    if (!q.length)
      return root.allApps
    const out = []
    for (let i = 0; i < root.allApps.length; i++) {
      const a = root.allApps[i]
      const hay = (a.title + " " + a.tag + " " + a.id).toLowerCase()
      if (hay.indexOf(q) >= 0)
        out.push(a)
    }
    return out
  }
}
