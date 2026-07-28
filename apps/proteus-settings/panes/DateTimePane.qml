import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Date & time: clock, timezone, network time, locale.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  property bool active: false
  property string zoneQuery: ""
  property bool pickingZone: false

  readonly property var zoneResults: root.pickingZone
      ? DateTime.searchTimezones(root.zoneQuery, 40)
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
    } else {
      root.pickingZone = false
      root.zoneQuery = ""
    }
  }

  Component.onCompleted: {
    if (active) {
      DateTime.refresh()
      DateTime.loadTimezones()
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

  SettingsGroup {
    title: "Locale"

    SettingsFormRow {
      label: "System locale"
      hint: DateTime.locale.length ? DateTime.locale : "Unset"
      showSeparator: true
    }

    SettingsFormRow {
      visible: DateTime.vcKeymap.length > 0
      label: "Console keymap"
      hint: DateTime.vcKeymap
      showSeparator: true
    }

    SettingsFormRow {
      label: "Edit locale.conf…"
      hint: "/etc/locale.conf"
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
    text: "Fact: timedatectl set-timezone / set-ntp (polkit-gated) · localectl status."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
