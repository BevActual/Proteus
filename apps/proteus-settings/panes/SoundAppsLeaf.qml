import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"
import "../kit"

// Leaf UI for SoundPane — Applications (FormRow polish).
ColumnLayout {
  id: root
  property Item host
  width: parent ? parent.width : implicitWidth
  spacing: Theme.spaceMd

  readonly property var apps: Audio.mixApps.length ? Audio.mixApps : (host ? host.apps : [])

  readonly property bool mixChannelsReady: {
    const ch = Audio.mixChannels || []
    if (!ch.length)
      return false
    for (let i = 0; i < ch.length; i++) {
      if (!ch[i].present)
        return false
    }
    return true
  }

  readonly property var assignComboModel: {
    const opts = []
    const raw = Audio.mixAssignOptions || []
    for (let i = 0; i < raw.length; i++) {
      const o = raw[i]
      if (!o || !o.id)
        continue
      opts.push({
        id: o.id,
        label: (o.kind === "mix" ? "" : "Out · ") + o.label
      })
    }
    return opts
  }

  function appHint(app) {
    if (!app)
      return ""
    if (!app.playing) {
      if (app.sink && app.sink.length)
        return "Saved · " + (app.sinkLabel || "channel")
      return "Not playing · assign a channel for next time"
    }
    const vol = (app.volume || 0) + "%"
    const route = app.sinkLabel || ""
    if (app.muted)
      return (app.detail && app.detail.length ? app.detail + " · " : "") + "muted"
    const bits = []
    if (app.detail && app.detail.length)
      bits.push(app.detail)
    bits.push(vol)
    if (route.length)
      bits.push(app.inMix ? ("Channel · " + route) : route)
    return bits.join(" · ")
  }

  SettingsGroup {
    title: "Mixer"

    SettingsFormRow {
      label: "Channels & routing"
      hint: "Group apps into Apps, Voice, Music, Browser, Game"
      showSeparator: false
      interactive: true
      onActivated: {
        if (host)
          host.requestGo("sound-matrix")
      }
      Text {
        text: "›"
        color: Theme.textMute
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }
    }
  }

  SettingsGroup {
    title: "Playing now"
    visible: root.apps.length === 0

    SettingsFormRow {
      label: "Applications"
      hint: "Apps show up after they’ve used audio — assign channels before you play"
      showSeparator: false
    }
  }

  SettingsGroup {
    visible: root.apps.length > 0
    title: "Playing now"

    Repeater {
      model: root.apps

      SettingsFormRow {
        required property var modelData
        required property int index
        label: modelData.name
        hint: root.appHint(modelData)
        showSeparator: index < root.apps.length - 1

        SettingsCombo {
          preferredWidth: 132
          enabled: !Audio.mixBusy && root.assignComboModel.length > 0 && !!modelData.id
          model: root.assignComboModel
          currentValue: modelData.sink || modelData.suggested || ""
          onActivated: v => {
            const cur = modelData.sink || ""
            if (!v.length || v === cur)
              return
            Audio.assignAppToSink(modelData.key || modelData.name, v, modelData.id || "")
            if (host)
              host.refreshAppsSoon.restart()
          }
        }

        ThemeSlider {
          Layout.preferredWidth: 120
          from: 0
          to: 100
          stepSize: 1
          value: modelData.volume
          visible: !!modelData.playing
          enabled: !!modelData.playing && !modelData.muted
          onMoved: {
            if (!host || !modelData.id)
              return
            const v = Math.round(value)
            Audio.setSinkInputVolume(modelData.id, v)
            host.patchApp(modelData.id, {
              volume: v
            })
          }
        }

        ThemeSwitch {
          visible: !!modelData.playing
          checked: !!modelData.muted
          onToggled: {
            if (!host || !modelData.id)
              return
            Audio.setSinkInputMute(modelData.id, checked)
            host.patchApp(modelData.id, {
              muted: checked
            })
            host.refreshAppsSoon.restart()
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    visible: Audio.mixError.length > 0
    text: Audio.mixError
    color: Theme.danger
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: pactl sink-inputs · move-sink-input · proteus_mix_* null sinks (audio-mix.py)."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
