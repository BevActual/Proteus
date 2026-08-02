import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf — soft Focus quiet (not a posture); profiles, allowlist, schedule.
ColumnLayout {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  property string appFilter: ""
  property string allowKeywordDraft: ""
  property string denyKeywordDraft: ""

  readonly property var dayLabels: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

  readonly property var profiles: {
    const _ = Config.focusProfiles
    const __ = Config.focusActiveProfileId
    return FocusMode.profiles()
  }

  readonly property var activeProfile: {
    const _ = Config.focusActiveProfileId
    return FocusMode.activeProfile()
  }

  readonly property var profileOptions: {
    const list = root.profiles || []
    const out = []
    for (let i = 0; i < list.length; i++) {
      if (!list[i])
        continue
      out.push({
        id: String(list[i].id || ""),
        label: String(list[i].name || list[i].id || "")
      })
    }
    return out
  }

  readonly property var sessionOptions: {
    const rows = [{ id: "off", label: "Off" }]
    for (let i = 0; i < FocusMode.modes.length; i++)
      rows.push({
        id: FocusMode.modes[i].id,
        label: FocusMode.modes[i].id === "indefinite" ? "Until off" : FocusMode.modes[i].title
      })
    return rows
  }

  readonly property var schedule: {
    const p = root.activeProfile
    const s = p && p.schedule && typeof p.schedule === "object" ? p.schedule : null
    return s || { enabled: false, start: "09:00", end: "17:00", days: [] }
  }

  readonly property var keywordAllow: {
    const p = root.activeProfile
    return (p && Array.isArray(p.keywordAllow)) ? p.keywordAllow : []
  }

  readonly property var keywordDeny: {
    const p = root.activeProfile
    return (p && Array.isArray(p.keywordDeny)) ? p.keywordDeny : []
  }

  readonly property var appCandidates: {
    const _m = Config.focusProfiles
    const q = String(root.appFilter || "").trim().toLowerCase()
    const allowed = FocusMode.allowedAppsList()
    const allowedSet = {}
    for (let a = 0; a < allowed.length; a++)
      allowedSet[FocusMode.normalizeAppKey(allowed[a])] = true

    const apps = DesktopEntries.applications.values
    const out = []
    for (let i = 0; i < apps.length; i++) {
      const a = apps[i]
      if (!a || !a.name)
        continue
      const id = String(a.id || "").replace(/\.desktop$/i, "")
      if (!id.length)
        continue
      const hay = (String(a.name) + " " + String(a.genericName || "") + " " + id).toLowerCase()
      if (q.length && hay.indexOf(q) < 0)
        continue
      out.push({
        id: id,
        name: String(a.name),
        allowed: !!allowedSet[FocusMode.normalizeAppKey(id)]
      })
      if (out.length >= 64)
        break
    }
    out.sort((x, y) => String(x.name).localeCompare(String(y.name)))
    return out
  }

  function scheduleDayOn(dow) {
    const days = Array.isArray(root.schedule.days) ? root.schedule.days : []
    for (let i = 0; i < days.length; i++) {
      if (Number(days[i]) === dow || String(days[i]) === String(dow))
        return true
    }
    return false
  }

  function patchSchedule(patch) {
    const base = {
      enabled: !!root.schedule.enabled,
      start: String(root.schedule.start || "09:00"),
      end: String(root.schedule.end || "17:00"),
      days: Array.isArray(root.schedule.days) ? root.schedule.days.slice() : []
    }
    FocusMode.updateActiveProfile({ schedule: Object.assign(base, patch || {}) })
  }

  function toggleScheduleDay(dow) {
    let days = Array.isArray(root.schedule.days) ? root.schedule.days.slice() : []
    let found = -1
    for (let i = 0; i < days.length; i++) {
      if (Number(days[i]) === dow || String(days[i]) === String(dow)) {
        found = i
        break
      }
    }
    if (found >= 0)
      days.splice(found, 1)
    else
      days.push(dow)
    days.sort((a, b) => Number(a) - Number(b))
    root.patchSchedule({ days: days })
  }

  function addKeyword(kind, text) {
    const word = String(text || "").trim()
    if (!word.length)
      return false
    const key = kind === "deny" ? "keywordDeny" : "keywordAllow"
    const cur = kind === "deny" ? root.keywordDeny.slice() : root.keywordAllow.slice()
    for (let i = 0; i < cur.length; i++) {
      if (String(cur[i]).trim().toLowerCase() === word.toLowerCase())
        return false
    }
    cur.push(word)
    const patch = {}
    patch[key] = cur
    FocusMode.updateActiveProfile(patch)
    return true
  }

  function removeKeyword(kind, word) {
    const key = kind === "deny" ? "keywordDeny" : "keywordAllow"
    const cur = kind === "deny" ? root.keywordDeny.slice() : root.keywordAllow.slice()
    const needle = String(word || "").trim().toLowerCase()
    const next = []
    for (let i = 0; i < cur.length; i++) {
      if (String(cur[i]).trim().toLowerCase() !== needle)
        next.push(cur[i])
    }
    const patch = {}
    patch[key] = next
    FocusMode.updateActiveProfile(patch)
  }

  Component.onCompleted: FocusMode.ensureProfilesPersisted()

  SettingsGroup {
    title: "Focus"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      Layout.bottomMargin: Theme.spaceSm
      text: "Soft quiet for toasts — not a posture. Start or stop quickly from Control Center; configure filters here."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    SettingsFormRow {
      label: "Profile"
      hint: root.activeProfile ? String(root.activeProfile.name || root.activeProfile.id || "") : "Work"
      showSeparator: true
      SettingsSegmented {
        Layout.preferredWidth: Math.min(280, parent.width)
        options: root.profileOptions
        selected: FocusMode.activeProfileId()
        onActivated: id => FocusMode.setActiveProfileId(id)
      }
    }

    SettingsFormRow {
      label: "Session"
      hint: FocusMode.active ? FocusMode.label : "Off"
      showSeparator: true
      SettingsSegmented {
        Layout.fillWidth: true
        options: root.sessionOptions
        selected: FocusMode.mode
        onActivated: id => FocusMode.select(id)
      }
    }

    SettingsFormRow {
      label: "Break through critical"
      hint: "Urgent notifications still toast when Focus is on"
      showSeparator: false
      ThemeSwitch {
        checked: FocusMode.breakCritical()
        onToggled: FocusMode.setBreakCritical(checked)
      }
    }
  }

  SettingsGroup {
    title: "Allowed apps"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Only these apps may toast while Focus is active (unless a keyword rule matches)."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    SettingsFormRow {
      label: "Search apps"
      hint: "Installed desktop entries"
      showSeparator: root.appCandidates.length > 0
      TextField {
        Layout.preferredWidth: 180
        placeholderText: "Filter…"
        text: root.appFilter
        color: Theme.text
        placeholderTextColor: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        background: Item {}
        onTextChanged: root.appFilter = text
      }
    }

    Repeater {
      model: root.appCandidates

      delegate: SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name
        hint: modelData.allowed ? "Allowed" : "Blocked"
        labelColor: modelData.allowed ? Theme.accent : Theme.text
        showSeparator: index < root.appCandidates.length - 1
        ThemeSwitch {
          checked: modelData.allowed
          onToggled: {
            if (checked)
              FocusMode.addAllowedApp(modelData.id)
            else
              FocusMode.removeAllowedApp(modelData.id)
          }
        }
      }
    }

    Text {
      visible: root.appCandidates.length === 0
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.bottomMargin: Theme.spaceMd
      text: root.appFilter.length
          ? "No apps match that filter."
          : "No desktop apps found — install apps or clear the filter."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }
  }

  SettingsGroup {
    title: "Keyword allow"

    SettingsFormRow {
      label: "Add keyword"
      hint: "Matches notification title or body"
      showSeparator: root.keywordAllow.length > 0
      TextField {
        id: allowField
        Layout.preferredWidth: 160
        placeholderText: "urgent"
        text: root.allowKeywordDraft
        color: Theme.text
        placeholderTextColor: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        background: Item {}
        onTextChanged: root.allowKeywordDraft = text
        onAccepted: {
          if (root.addKeyword("allow", text))
            text = ""
        }
      }
      Text {
        text: "Add"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.addKeyword("allow", allowField.text))
              allowField.text = ""
          }
        }
      }
    }

    Repeater {
      model: root.keywordAllow

      delegate: SettingsFormRow {
        required property var modelData
        required property int index
        label: String(modelData)
        hint: "Allow toast"
        showSeparator: index < root.keywordAllow.length - 1
        Text {
          text: "Remove"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 13
          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeKeyword("allow", modelData)
          }
        }
      }
    }

    Text {
      visible: root.keywordAllow.length === 0
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.bottomMargin: Theme.spaceMd
      text: "No allow keywords — only allowed apps (and critical, if enabled) toast."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }
  }

  SettingsGroup {
    title: "Keyword deny"

    SettingsFormRow {
      label: "Add keyword"
      hint: "Blocks even if the app is allowed"
      showSeparator: root.keywordDeny.length > 0
      TextField {
        id: denyField
        Layout.preferredWidth: 160
        placeholderText: "promo"
        text: root.denyKeywordDraft
        color: Theme.text
        placeholderTextColor: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        background: Item {}
        onTextChanged: root.denyKeywordDraft = text
        onAccepted: {
          if (root.addKeyword("deny", text))
            text = ""
        }
      }
      Text {
        text: "Add"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.addKeyword("deny", denyField.text))
              denyField.text = ""
          }
        }
      }
    }

    Repeater {
      model: root.keywordDeny

      delegate: SettingsFormRow {
        required property var modelData
        required property int index
        label: String(modelData)
        hint: "Block toast"
        showSeparator: index < root.keywordDeny.length - 1
        Text {
          text: "Remove"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 13
          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeKeyword("deny", modelData)
          }
        }
      }
    }

    Text {
      visible: root.keywordDeny.length === 0
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.bottomMargin: Theme.spaceMd
      text: "No deny keywords."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }
  }

  SettingsGroup {
    title: "Schedule"

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: Theme.spaceMd
      Layout.rightMargin: Theme.spaceMd
      Layout.topMargin: Theme.spaceSm
      text: "Automatically turn Focus on for this profile during the window below."
      color: Theme.textMute
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSizeSm
      wrapMode: Text.WordWrap
    }

    SettingsFormRow {
      label: "Enable schedule"
      hint: root.schedule.enabled ? "Active for this profile" : "Off"
      showSeparator: true
      ThemeSwitch {
        checked: root.schedule.enabled
        onToggled: root.patchSchedule({ enabled: checked })
      }
    }

    SettingsFormRow {
      label: "Start"
      hint: "HH:mm"
      showSeparator: true
      TextField {
        Layout.preferredWidth: 72
        enabled: root.schedule.enabled
        text: String(root.schedule.start || "09:00")
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        placeholderText: "09:00"
        placeholderTextColor: Theme.textMute
        background: Item {}
        onEditingFinished: root.patchSchedule({ start: text.trim() || "09:00" })
      }
    }

    SettingsFormRow {
      label: "End"
      hint: "HH:mm"
      showSeparator: true
      TextField {
        Layout.preferredWidth: 72
        enabled: root.schedule.enabled
        text: String(root.schedule.end || "17:00")
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        placeholderText: "17:00"
        placeholderTextColor: Theme.textMute
        background: Item {}
        onEditingFinished: root.patchSchedule({ end: text.trim() || "17:00" })
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: dayRow.implicitHeight + Theme.spaceMd * 2
      visible: root.schedule.enabled

      Row {
        id: dayRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.spaceMd
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
          model: 7

          Rectangle {
            required property int index
            readonly property int dow: index
            readonly property bool on: root.scheduleDayOn(dow)
            width: 36
            height: 28
            radius: Theme.radiusSm
            color: on ? Theme.accentSoft : Theme.bgHover
            border.width: on ? 1 : 0
            border.color: Theme.accent

            Text {
              anchors.centerIn: parent
              text: root.dayLabels[dow]
              color: on ? Theme.accent : Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.bold: on
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleScheduleDay(dow)
            }
          }
        }
      }
    }
  }

  SettingsGroup {
    title: "Hard quiet"

    SettingsFormRow {
      label: "Do Not Disturb"
      hint: "Suppresses all toasts — ignores Focus allowlist"
      showSeparator: false
      ThemeSwitch {
        checked: Config.notificationsDnd
        onToggled: Notifications.setDnd(checked)
      }
    }
  }
}
