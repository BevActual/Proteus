import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: 12

  property bool active: false
  property int volume: 50
  property bool muted: false
  property int inputVolume: 50
  property bool inputMuted: false
  property var sinks: []
  property var sources: []
  property string status: ""
  property string clockSummary: ""

  function formatState(state) {
    const s = state || "unknown"
    if (s === "SUSPENDED")
      return "Idle (starts on play)"
    return s
  }

  function refresh() {
    status = ""
    Config.getVolume(v => {
      root.volume = v
    })
    Config.getMute(m => {
      root.muted = m
    })
    Config.getSourceVolume(v => {
      root.inputVolume = v
    })
    Config.getSourceMute(m => {
      root.inputMuted = m
    })
    Config.listSinks(list => {
      root.sinks = list || []
      if (!root.sinks.length) {
        root.status = "No output devices (is PipeWire / Pulse running?)."
        return
      }
      const def = root.sinks.find(s => s.isDefault)
      const better = root.sinks.find(s => s.name && s.name.indexOf("null") < 0)
      if (def && def.name && def.name.indexOf("null") >= 0 && better) {
        Config.setDefaultSink(better.name)
        refreshTimer.restart()
        return
      }
      root.status = ""
    })
    Config.listSources(list => {
      root.sources = list || []
    })
    Config.getPipeWireClock(info => {
      if (!info || (!info.rate && !info.forceQuantum && !info.quantum)) {
        root.clockSummary = ""
        return
      }
      const rate = info.rate ? (info.rate + " Hz") : "rate ?"
      const frames = info.forceQuantum > 0 ? info.forceQuantum : info.quantum
      const forced = info.forceQuantum > 0
      const buf = frames ? (frames + " frames" + (forced ? " forced" : "")) : ""
      root.clockSummary = buf.length ? (rate + " · " + buf) : rate
    })
    Config.applyAudioLatency()
  }

  function selectSink(name) {
    if (!name || !String(name).length)
      return
    Config.setDefaultSink(name)
    refreshTimer.restart()
  }

  function selectSource(name) {
    if (!name || !String(name).length)
      return
    Config.setDefaultSource(name)
    refreshTimer.restart()
  }

  readonly property var defaultSink: root.sinks.find(s => s.isDefault) || null
  readonly property var defaultSource: root.sources.find(s => s.isDefault) || null

  Timer {
    id: refreshTimer
    interval: 200
    repeat: false
    onTriggered: root.refresh()
  }

  Text {
    Layout.fillWidth: true
    text: "Output and input levels, devices, and PipeWire buffer size."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  Text {
    text: "Output"
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
  }

  Text {
    text: "Volume"
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 11
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    Slider {
      Layout.fillWidth: true
      from: 0
      to: 100
      stepSize: 1
      value: root.volume
      enabled: !root.muted
      onMoved: {
        root.volume = Math.round(value)
        Config.setVolume(root.volume)
      }
    }
    Text {
      text: root.volume + "%"
      color: Theme.text
      font.family: Theme.fontFamily
      Layout.preferredWidth: 42
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    Layout.preferredHeight: 48
    radius: Theme.radiusMd
    color: Theme.bgPanel
    border.width: 1
    border.color: Theme.border
    RowLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceMd
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Text {
          text: "Mute output"
          color: Theme.text
          font.family: Theme.fontFamily
        }
        Text {
          text: root.muted ? "Silenced" : "Audible"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
      }
      Switch {
        checked: root.muted
        onToggled: {
          root.muted = checked
          Config.setMute(checked)
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: !!root.defaultSink
    text: "Default: " + root.defaultSink.label
        + (root.defaultSink.sample ? (" · " + root.defaultSink.sample) : "")
        + " · " + root.formatState(root.defaultSink.state)
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.sinks

    Rectangle {
      required property var modelData
      Layout.fillWidth: true
      Layout.maximumWidth: 420
      Layout.preferredHeight: sinkCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: modelData.isDefault ? Theme.accentSoft : Theme.bgPanel
      border.width: modelData.isDefault ? 2 : 1
      border.color: modelData.isDefault ? Theme.accent : Theme.border

      ColumnLayout {
        id: sinkCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: 2

        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            text: modelData.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.bold: !!modelData.isDefault
          }
          Text {
            visible: !!modelData.isDefault
            text: "Default"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }

        Text {
          Layout.fillWidth: true
          text: modelData.name
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 10
          elide: Text.ElideMiddle
        }

        Text {
          Layout.fillWidth: true
          text: root.formatState(modelData.state)
              + (modelData.sample ? (" · " + modelData.sample) : "")
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: !modelData.isDefault
        onClicked: root.selectSink(modelData.name)
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.topMargin: 4
    text: "Latency / buffer"
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    text: "PipeWire quantum — higher is smoother, lower is snappier."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    spacing: 8

    Repeater {
      model: Config.audioLatencyProfiles

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: Theme.radiusMd
        color: Config.audioLatency === modelData.id ? Theme.accentSoft : Theme.bgPanel
        border.width: Config.audioLatency === modelData.id ? 2 : 1
        border.color: Config.audioLatency === modelData.id ? Theme.accent : Theme.border

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Theme.spaceMd
          spacing: 2
          Text {
            text: modelData.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: Config.audioLatency === modelData.id
          }
          Text {
            Layout.fillWidth: true
            text: modelData.hint
            color: Theme.textMute
            font.family: Theme.fontFamily
            font.pixelSize: 10
            wrapMode: Text.WordWrap
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            Config.setAudioLatency(modelData.id)
            refreshTimer.restart()
          }
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    visible: root.clockSummary.length > 0
    text: "PipeWire: " + root.clockSummary
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    Layout.topMargin: 8
    text: "Input"
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSm
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    visible: !root.sources.length
    text: "No capture devices reported."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Text {
    visible: root.sources.length > 0
    text: "Microphone level"
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 11
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    visible: root.sources.length > 0
    Slider {
      Layout.fillWidth: true
      from: 0
      to: 100
      stepSize: 1
      value: root.inputVolume
      enabled: !root.inputMuted
      onMoved: {
        root.inputVolume = Math.round(value)
        Config.setSourceVolume(root.inputVolume)
      }
    }
    Text {
      text: root.inputVolume + "%"
      color: Theme.text
      font.family: Theme.fontFamily
      Layout.preferredWidth: 42
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    Layout.preferredHeight: 48
    visible: root.sources.length > 0
    radius: Theme.radiusMd
    color: Theme.bgPanel
    border.width: 1
    border.color: Theme.border
    RowLayout {
      anchors.fill: parent
      anchors.margins: Theme.spaceMd
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Text {
          text: "Mute input"
          color: Theme.text
          font.family: Theme.fontFamily
        }
        Text {
          text: root.inputMuted ? "Muted" : "Live"
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
      }
      Switch {
        checked: root.inputMuted
        onToggled: {
          root.inputMuted = checked
          Config.setSourceMute(checked)
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: !!root.defaultSource
    text: "Default: " + root.defaultSource.label
        + (root.defaultSource.sample ? (" · " + root.defaultSource.sample) : "")
        + " · " + root.formatState(root.defaultSource.state)
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.sources

    Rectangle {
      required property var modelData
      Layout.fillWidth: true
      Layout.maximumWidth: 420
      Layout.preferredHeight: srcCol.implicitHeight + 20
      radius: Theme.radiusMd
      color: modelData.isDefault ? Theme.accentSoft : Theme.bgPanel
      border.width: modelData.isDefault ? 2 : 1
      border.color: modelData.isDefault ? Theme.accent : Theme.border

      ColumnLayout {
        id: srcCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spaceMd
        spacing: 2

        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            text: modelData.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.bold: !!modelData.isDefault
          }
          Text {
            visible: !!modelData.isDefault
            text: "Default"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }

        Text {
          Layout.fillWidth: true
          text: modelData.name
          color: Theme.textMute
          font.family: Theme.fontFamily
          font.pixelSize: 10
          elide: Text.ElideMiddle
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: !modelData.isDefault
        onClicked: root.selectSource(modelData.name)
      }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: root.status.length > 0
    text: root.status
    color: Theme.textDim
    font.family: Theme.fontFamily
    font.pixelSize: 12
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    spacing: 8

    Button {
      text: "Test sound"
      onClicked: Config.playTestSound()
    }

    Button {
      text: "Refresh"
      onClicked: root.refresh()
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 420
    Layout.topMargin: 4
    text: "Fact: pactl for levels/devices · pw-metadata for buffer quantum."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }

  onActiveChanged: {
    if (active)
      refresh()
  }

  Component.onCompleted: {
    if (active)
      refresh()
  }
}
