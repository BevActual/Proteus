import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Date & time: clock, timezone, network time, locale.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false
  property string zoneQuery: ""
  property bool pickingZone: false
  property string placeQuery: ""
  property bool pickingPlace: false
  property string localeQuery: ""
  property bool pickingLocale: false

  // Geocoding is a network call per keystroke otherwise.
  Timer {
    id: placeDebounce
    interval: 350
    repeat: false
    onTriggered: Weather.searchPlaces(root.placeQuery)
  }

  readonly property var zoneResults: root.pickingZone
      ? DateTime.searchTimezones(root.zoneQuery, 40)
      : []

  readonly property var localeResults: root.pickingLocale
      ? DateTime.searchLocales(root.localeQuery, 40)
      : []

  // Live clock rendered in the selected zone — SystemClock ticks locally, and
  // the zone is applied by the system, so this reflects the real setting.
  SystemClock {
    id: clock
    precision: SystemClock.Seconds
  }

  function friendlyZone(tz) {
    return String(tz || "").replace(/_/g, " ")
  }

  onActiveChanged: {
    if (active) {
      DateTime.refresh()
      DateTime.loadTimezones()
      DateTime.loadLocales()
    } else {
      root.pickingZone = false
      root.zoneQuery = ""
      root.pickingPlace = false
      root.placeQuery = ""
      root.pickingLocale = false
      root.localeQuery = ""
      Weather.clearSearch()
    }
  }

  Component.onCompleted: {
    if (active) {
      DateTime.refresh()
      DateTime.loadTimezones()
      DateTime.loadLocales()
    }
  }

  SettingsGroup {
    title: "Clock"

    SettingsFormRow {
      label: Qt.formatDateTime(clock.date, "h:mm:ss AP")
      hint: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "Time zone"

    SettingsFormRow {
      label: "Time zone"
      hint: DateTime.timezone.length
          ? root.friendlyZone(DateTime.timezone)
          : "Unknown"
      showSeparator: root.pickingZone
      interactive: true
      onActivated: {
        root.pickingZone = !root.pickingZone
        root.zoneQuery = ""
      }
      Text {
        text: root.pickingZone ? "Cancel" : "Change"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    // Search box — 598 zones is far too many for a combo box.
    Item {
      visible: root.pickingZone
      Layout.fillWidth: true
      Layout.preferredHeight: 44

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        anchors.topMargin: Theme.spaceXs
        anchors.bottomMargin: Theme.spaceSm
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: zoneSearch.activeFocus ? Theme.accent : Theme.border

        TextInput {
          id: zoneSearch
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          verticalAlignment: TextInput.AlignVCenter
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          selectByMouse: true
          clip: true
          text: root.zoneQuery
          onTextChanged: root.zoneQuery = text

          Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            text: DateTime.loadingZones ? "Loading zones…" : "Search — city or region"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            visible: !zoneSearch.text.length && !zoneSearch.activeFocus
          }
        }
      }
    }

    Repeater {
      model: root.zoneResults

      SettingsFormRow {
        required property var modelData
        required property int index
        label: root.friendlyZone(modelData)
        hint: modelData === DateTime.timezone ? "Current" : ""
        showSeparator: index < root.zoneResults.length - 1
        interactive: modelData !== DateTime.timezone
        onActivated: {
          DateTime.setTimezone(modelData)
          root.pickingZone = false
          root.zoneQuery = ""
        }
        Text {
          visible: modelData === DateTime.timezone
          text: "✓"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 13
        }
      }
    }

    SettingsFormRow {
      visible: root.pickingZone && !DateTime.loadingZones && root.zoneResults.length === 0
      label: "No matching zone"
      hint: "Try a city or region name"
      showSeparator: false
    }
  }

  SettingsGroup {
    title: "Network time"

    SettingsFormRow {
      label: "Set automatically"
      hint: DateTime.canNtp ? DateTime.ntpStatus : "No time sync service available"
      showSeparator: true
      Switch {
        checked: DateTime.ntp
        enabled: DateTime.canNtp && !DateTime.busy
        onToggled: DateTime.setNtp(checked)
      }
    }

    SettingsFormRow {
      label: "Hardware clock"
      hint: DateTime.localRtc ? "Local time — may confuse dual boot" : "UTC (recommended)"
      showSeparator: false
    }
  }

  // Location is system state, not a per-widget setting: set it once and every
  // surface that needs "where am I" uses it. Explicit search only — coarse IP
  // geolocation is what puts weather in the wrong town with no way to fix it.
  SettingsGroup {
    title: "Location"

    SettingsFormRow {
      label: "Place"
      hint: Config.locationName.length
          ? (Config.locationName + " · "
             + Number(Config.locationLatitude).toFixed(3) + ", "
             + Number(Config.locationLongitude).toFixed(3))
          : "Not set — weather and sunrise need this"
      showSeparator: root.pickingPlace || Config.locationName.length > 0
      interactive: true
      onActivated: {
        root.pickingPlace = !root.pickingPlace
        root.placeQuery = ""
        Weather.clearSearch()
      }
      Text {
        text: root.pickingPlace ? "Cancel" : (Config.locationName.length ? "Change" : "Set")
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    Item {
      visible: root.pickingPlace
      Layout.fillWidth: true
      Layout.preferredHeight: 44

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        anchors.topMargin: Theme.spaceXs
        anchors.bottomMargin: Theme.spaceSm
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: placeSearch.activeFocus ? Theme.accent : Theme.border

        TextInput {
          id: placeSearch
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          verticalAlignment: TextInput.AlignVCenter
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          selectByMouse: true
          clip: true
          text: root.placeQuery
          onTextChanged: {
            root.placeQuery = text
            placeDebounce.restart()
          }
          Keys.onReturnPressed: Weather.searchPlaces(root.placeQuery)

          Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            text: Weather.searching ? "Searching…" : "Town or city — then pick the right one"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            visible: !placeSearch.text.length && !placeSearch.activeFocus
          }
        }
      }
    }

    Repeater {
      model: root.pickingPlace ? Weather.searchResults : []

      SettingsFormRow {
        required property var modelData
        required property int index
        // Region and country are what separate five Springfields.
        label: modelData.label
        hint: Number(modelData.latitude).toFixed(3) + ", "
            + Number(modelData.longitude).toFixed(3)
            + (modelData.timezone.length ? (" · " + modelData.timezone) : "")
        showSeparator: index < Weather.searchResults.length - 1
        interactive: true
        onActivated: {
          Weather.setLocation(modelData)
          root.pickingPlace = false
          root.placeQuery = ""
          Weather.clearSearch()
        }
        Text {
          text: "Use"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }
      }
    }

    SettingsFormRow {
      visible: root.pickingPlace && Weather.searchError.length > 0
      label: Weather.searchError
      labelColor: Theme.textMute
      hint: "Try a nearby larger town"
      showSeparator: false
    }

    SettingsFormRow {
      visible: !root.pickingPlace && !Config.weatherEnabled
      label: "Weather fetch"
      hint: "Off — Open-Meteo muted under Privacy"
      showSeparator: Config.locationName.length > 0
    }

    SettingsFormRow {
      visible: !root.pickingPlace && Config.locationName.length > 0
      label: "Units"
      hint: Weather.imperial ? "Fahrenheit and miles per hour" : "Celsius and kilometres per hour"
      showSeparator: true
      SettingsSegmented {
        Layout.preferredWidth: 160
        options: [
          {
            id: "metric",
            label: "°C"
          },
          {
            id: "imperial",
            label: "°F"
          }
        ]
        selected: Config.weatherUnits
        onActivated: id => Weather.setUnits(id)
      }
    }

    SettingsFormRow {
      visible: !root.pickingPlace && Config.locationName.length > 0
      label: "Conditions"
      hint: Weather.conditionsDetail
      showSeparator: true
      interactive: Config.weatherEnabled
      onActivated: Weather.refresh()
      Text {
        text: !Config.weatherEnabled
            ? "Muted"
            : (Weather.loading ? "…" : "Refresh")
        color: Config.weatherEnabled ? Theme.accent : Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      // Offer sync when Open-Meteo place TZ differs from the system zone.
      visible: !root.pickingPlace
          && Config.locationName.length > 0
          && Config.locationTimezone.length > 0
          && Config.locationTimezone !== DateTime.timezone
      label: "Match time zone to place"
      hint: root.friendlyZone(Config.locationTimezone)
          + " · system is "
          + (DateTime.timezone.length ? root.friendlyZone(DateTime.timezone) : "unset")
          + " · polkit"
      showSeparator: Weather.hasForecast || Config.locationName.length > 0
      interactive: !DateTime.busy
      onActivated: DateTime.setTimezone(Config.locationTimezone)
      Text {
        text: DateTime.busy ? "…" : "Apply"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    SettingsFormRow {
      visible: !root.pickingPlace
          && Config.locationName.length > 0
          && Config.locationTimezone.length > 0
          && Config.locationTimezone === DateTime.timezone
      label: "Place time zone"
      hint: root.friendlyZone(Config.locationTimezone) + " · matches system"
      showSeparator: Weather.hasForecast || Config.locationName.length > 0
    }

    Repeater {
      model: (!root.pickingPlace && Config.locationName.length > 0)
          ? Weather.forecast
          : []

      SettingsFormRow {
        required property var modelData
        required property int index
        label: Weather.forecastDayLabel(modelData.date, index)
        hint: (modelData.description.length ? (modelData.description + " · ") : "")
            + Weather.forecastRangeText(modelData)
        showSeparator: index < Weather.forecast.length - 1
            || Config.locationName.length > 0
      }
    }

    SettingsFormRow {
      visible: !root.pickingPlace && Config.locationName.length > 0
      label: "Clear location"
      hint: "Stops weather lookups entirely"
      labelColor: Theme.danger
      showSeparator: false
      interactive: true
      onActivated: Weather.clearLocation()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Locale"

    SettingsFormRow {
      label: "System locale"
      hint: DateTime.locale.length ? DateTime.locale : "Unset"
      showSeparator: root.pickingLocale || DateTime.vcKeymap.length > 0
      interactive: !DateTime.busy
      onActivated: {
        root.pickingLocale = !root.pickingLocale
        root.localeQuery = ""
        if (root.pickingLocale)
          DateTime.loadLocales()
      }
      Text {
        text: root.pickingLocale ? "Cancel" : "Change"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }
    }

    Item {
      visible: root.pickingLocale
      Layout.fillWidth: true
      Layout.preferredHeight: 44

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: Theme.spaceMd
        anchors.topMargin: Theme.spaceXs
        anchors.bottomMargin: Theme.spaceSm
        radius: Theme.radiusMd
        color: Theme.bgHover
        border.width: 1
        border.color: localeSearch.activeFocus ? Theme.accent : Theme.border

        TextInput {
          id: localeSearch
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: Theme.spaceMd
          verticalAlignment: TextInput.AlignVCenter
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize
          selectByMouse: true
          clip: true
          text: root.localeQuery
          onTextChanged: root.localeQuery = text

          Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            text: DateTime.loadingLocales ? "Loading locales…" : "Search — e.g. en_US or utf"
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            visible: !localeSearch.text.length && !localeSearch.activeFocus
          }
        }
      }
    }

    Repeater {
      model: root.localeResults

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData
        hint: modelData === DateTime.locale ? "Current" : ""
        showSeparator: index < root.localeResults.length - 1
        interactive: modelData !== DateTime.locale && !DateTime.busy
        onActivated: {
          DateTime.setLocale(modelData)
          root.pickingLocale = false
          root.localeQuery = ""
        }
        Text {
          visible: modelData === DateTime.locale
          text: "✓"
          color: Theme.accent
          font.family: Theme.fontFamily
          font.pixelSize: 13
        }
      }
    }

    SettingsFormRow {
      visible: root.pickingLocale && !DateTime.loadingLocales && root.localeResults.length === 0
      label: "No matching locale"
      hint: "Generate locales on the host, or Edit locale.conf…"
      showSeparator: false
    }

    SettingsFormRow {
      visible: DateTime.vcKeymap.length > 0
      label: "Console keymap"
      hint: DateTime.vcKeymap
      showSeparator: true
    }

    SettingsFormRow {
      label: "Edit locale.conf…"
      hint: "/etc/locale.conf · escape hatch"
      showSeparator: false
      interactive: true
      onActivated: DateTime.openLocaleConf()
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: DateTime.error.length > 0
    text: DateTime.error
    color: Theme.danger
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: timedatectl set-timezone / set-ntp · localectl set-locale LANG=… (polkit-gated) · "
        + "weather from api.open-meteo.com (no API key). Only the coordinates you set are sent."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
