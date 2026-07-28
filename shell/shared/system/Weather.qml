pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import ".."

// Current conditions for the configured system location.
//
// Location is never inferred from IP — it comes from an explicit place search
// in Settings (Config.location*), which is the whole point: coarse geolocation
// is what puts weather in the wrong town with no way to correct it.
//
// Backed by Open-Meteo, which needs no API key, so there is no credential to
// store. Only the coordinates you set leave the machine.
Singleton {
  id: root

  readonly property bool hasLocation: Config.locationName.length > 0
      && !(Config.locationLatitude === 0 && Config.locationLongitude === 0)

  readonly property bool imperial: Config.weatherUnits === "imperial"

  property bool loading: false
  property string error: ""
  property string fetchedAt: ""

  property real temperature: 0
  property real apparent: 0
  property int humidity: 0
  property real windSpeed: 0
  property bool isDay: true
  property int code: -1
  property string description: ""
  property real high: 0
  property real low: 0
  property string sunrise: ""
  property string sunset: ""
  property string tempUnit: "°C"
  property string windUnit: "km/h"

  readonly property bool ready: root.code >= 0 && root.error.length === 0

  // Place search state (Settings → Date & time → Location)
  property bool searching: false
  property var searchResults: []
  property string searchError: ""

  // Config already resolves this for the shell, the wallpaper instance and the
  // Settings app — no reason for a second copy to drift from it.
  readonly property string scriptsDir: Config.scriptsDir

  readonly property string temperatureText: root.ready
      ? (Math.round(root.temperature) + root.tempUnit)
      : "—"

  readonly property string summary: {
    if (!root.hasLocation)
      return "No location set"
    if (root.error.length)
      return root.error
    if (root.loading && !root.ready)
      return "Updating…"
    if (!root.ready)
      return "No data yet"
    return root.description + " · " + root.temperatureText
  }

  // Coarse glyph for the widget; WMO buckets, day/night aware.
  readonly property string glyph: {
    const c = root.code
    if (c < 0)
      return "•"
    if (c === 0 || c === 1)
      return root.isDay ? "☀" : "☾"
    if (c === 2)
      return "⛅"
    if (c === 3)
      return "☁"
    if (c === 45 || c === 48)
      return "≡"
    if (c >= 51 && c <= 57)
      return "☂"
    if (c >= 61 && c <= 67)
      return "☔"
    if (c >= 71 && c <= 77)
      return "❄"
    if (c >= 80 && c <= 82)
      return "☔"
    if (c === 85 || c === 86)
      return "❄"
    if (c >= 95)
      return "⚡"
    return "•"
  }

  function refresh() {
    if (!hasLocation || fetchProc.running)
      return
    root.loading = true
    root.error = ""
    const args = [
      "python3",
      scriptsDir + "/fetch-weather.py",
      "--lat",
      String(Config.locationLatitude),
      "--lon",
      String(Config.locationLongitude)
    ]
    if (root.imperial)
      args.push("--imperial")
    fetchProc.command = args
    fetchProc.running = false
    fetchProc.running = true
  }

  function searchPlaces(query) {
    const q = String(query || "").trim()
    if (!q.length) {
      root.searchResults = []
      root.searchError = ""
      return
    }
    root.searching = true
    root.searchError = ""
    searchProc.command = [
      "python3",
      scriptsDir + "/fetch-weather.py",
      "--search",
      q
    ]
    searchProc.running = false
    searchProc.running = true
  }

  function clearSearch() {
    root.searchResults = []
    root.searchError = ""
    root.searching = false
  }

  // Store the picked place. Coordinates are kept exactly as geocoded so the
  // forecast is for that place, not a region centroid.
  function setLocation(place) {
    if (!place)
      return
    Config.locationName = String(place.label || place.name || "")
    Config.locationLatitude = Number(place.latitude) || 0
    Config.locationLongitude = Number(place.longitude) || 0
    Config.locationTimezone = String(place.timezone || "")
    Config.flushSettings()
    root.code = -1
    root.error = ""
    root.refresh()
  }

  function clearLocation() {
    Config.locationName = ""
    Config.locationLatitude = 0
    Config.locationLongitude = 0
    Config.locationTimezone = ""
    Config.flushSettings()
    root.code = -1
    root.error = ""
  }

  function setUnits(id) {
    const u = String(id || "metric")
    if (u !== "metric" && u !== "imperial")
      return
    if (u === Config.weatherUnits)
      return
    Config.weatherUnits = u
    Config.flushSettings()
    root.refresh()
  }

  Process {
    id: fetchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false
        const raw = text.trim()
        if (!raw.length) {
          root.error = "Weather fetch returned no data"
          return
        }
        try {
          const res = JSON.parse(raw.split("\n").filter(l => l.trim().length).pop())
          if (!res || !res.ok) {
            root.error = (res && res.error) ? String(res.error) : "Weather fetch failed"
            return
          }
          const c = res.current || {}
          const t = res.today || {}
          const u = res.units || {}
          root.temperature = Number(c.temperature) || 0
          root.apparent = Number(c.apparent) || 0
          root.humidity = Math.round(Number(c.humidity) || 0)
          root.windSpeed = Number(c.windSpeed) || 0
          root.isDay = !!c.isDay
          root.description = String(c.description || "")
          root.high = Number(t.high) || 0
          root.low = Number(t.low) || 0
          root.sunrise = String(t.sunrise || "")
          root.sunset = String(t.sunset || "")
          root.tempUnit = String(u.temperature || "°C")
          root.windUnit = String(u.windSpeed || "km/h")
          root.fetchedAt = String(c.observedAt || "")
          // Set last: `ready` keys off it, so everything else is in place first.
          root.code = (c.code === undefined || c.code === null) ? -1 : Number(c.code)
          root.error = ""
        } catch (e) {
          root.error = "Weather parse error"
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        const e = text.trim()
        if (e.length && root.loading)
          root.error = e.split("\n")[0]
      }
    }
  }

  Process {
    id: searchProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.searching = false
        try {
          const res = JSON.parse(text.trim() || "{}")
          if (!res.ok) {
            root.searchError = String(res.error || "Search failed")
            root.searchResults = []
            return
          }
          const list = Array.isArray(res.results) ? res.results : []
          root.searchResults = list.map(r => {
            // Disambiguate: "Springfield, Missouri, US" not just "Springfield".
            const parts = [r.name]
            if (r.admin1 && r.admin1.length)
              parts.push(r.admin1)
            if (r.countryCode && r.countryCode.length)
              parts.push(r.countryCode)
            return {
              label: parts.join(", "),
              name: r.name,
              admin1: r.admin1 || "",
              country: r.country || "",
              countryCode: r.countryCode || "",
              latitude: r.latitude,
              longitude: r.longitude,
              timezone: r.timezone || ""
            }
          })
          root.searchError = root.searchResults.length ? "" : "No matching place"
        } catch (e) {
          root.searchResults = []
          root.searchError = "Search parse error"
        }
      }
    }
  }

  onHasLocationChanged: {
    if (hasLocation)
      refresh()
  }

  Component.onCompleted: {
    if (hasLocation)
      refresh()
  }

  // Conditions move slowly; Open-Meteo updates on a 15-minute cadence.
  Timer {
    interval: 15 * 60 * 1000
    repeat: true
    running: root.hasLocation
    onTriggered: root.refresh()
  }
}
