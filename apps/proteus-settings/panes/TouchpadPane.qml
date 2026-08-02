import Quickshell
import QtQuick
import QtQuick.Layouts
import "../shared"
import "../kit"

// Peripherals → Touchpad leaf.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Theme.spaceMd

  readonly property string scrollLabel: {
    const v = Config.touchpadScrollFactor
    return v.toFixed(1) + "×"
  }

  SettingsGroup {
    title: "Touchpad"

    SettingsFormRow {
      label: "Natural scrolling"
      hint: Config.touchpadNaturalScroll ? "Content follows fingers" : "Off — classic direction"
      showSeparator: true
      ThemeSwitch {
        checked: Config.touchpadNaturalScroll
        onToggled: Config.touchpadNaturalScroll = checked
      }
    }

    SettingsFormRow {
      label: "Tap to click"
      hint: Config.touchpadTapToClick ? "1/2/3-finger taps" : "Off — physical click only"
      showSeparator: true
      ThemeSwitch {
        checked: Config.touchpadTapToClick
        onToggled: Config.touchpadTapToClick = checked
      }
    }

    SettingsFormRow {
      label: "Disable while typing"
      hint: Config.touchpadDisableWhileTyping ? "Ignores palm while typing" : "Off"
      showSeparator: true
      ThemeSwitch {
        checked: Config.touchpadDisableWhileTyping
        onToggled: Config.touchpadDisableWhileTyping = checked
      }
    }

    SettingsFormRow {
      label: "Clickfinger"
      hint: Config.touchpadClickfinger
          ? "Two-finger click = right · three = middle"
          : "Off — corner / button zones"
      showSeparator: true
      ThemeSwitch {
        checked: Config.touchpadClickfinger
        onToggled: Config.touchpadClickfinger = checked
      }
    }

    SettingsFormRow {
      label: "Scroll speed"
      hint: root.scrollLabel
      showSeparator: false
      ThemeSlider {
        Layout.preferredWidth: 150
        from: 0.1
        to: 3.0
        stepSize: 0.1
        value: Config.touchpadScrollFactor
        onMoved: Config.touchpadScrollFactor = Math.round(value * 10) / 10
      }
    }
  }

  Text {
    Layout.fillWidth: true
    Layout.maximumWidth: 480
    text: "Fact: settings.json + hyprctl input:touchpad:* → proteus-general.conf. Per-device device {} blocks stay Out."
    color: Theme.textMute
    font.family: Theme.fontFamily
    font.pixelSize: 11
    wrapMode: Text.WordWrap
  }
}
